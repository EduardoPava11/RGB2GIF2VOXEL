import AVFoundation
import CoreMedia
import Combine

/// Represents a camera format option with clean aperture detection
struct DeviceFormatOption: Identifiable, Equatable {
    let id = UUID()
    let format: AVCaptureDevice.Format
    let width: Int
    let height: Int
    let cleanWidth: Int
    let cleanHeight: Int
    let isSquareFormat: Bool
    let maxFPS: Double
    let minFPS: Double
    let formatDescription: String

    var aspectRatio: Double {
        Double(cleanWidth) / Double(cleanHeight)
    }

    var megapixels: Double {
        Double(cleanWidth * cleanHeight) / 1_000_000
    }

    var displayName: String {
        let squareLabel = isSquareFormat ? "□" : "▭"
        return "\(squareLabel) \(cleanWidth)×\(cleanHeight) @ \(Int(maxFPS))fps (\(String(format: "%.1f", megapixels))MP)"
    }

    static func == (lhs: DeviceFormatOption, rhs: DeviceFormatOption) -> Bool {
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.maxFPS == rhs.maxFPS
    }
}

/// Enhanced camera manager with format enumeration for iPhone 17 square sensor
@MainActor
class FrontCameraManager: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var availableFormats: [DeviceFormatOption] = []
    @Published var selectedFormat: DeviceFormatOption?
    @Published var isSessionRunning = false
    @Published var errorMessage: String?

    // MARK: - Camera Properties
    private let captureSession = AVCaptureSession()
    private var frontCamera: AVCaptureDevice?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.yingif.camera.session")
    private let videoDataQueue = DispatchQueue(label: "com.yingif.camera.videodata")

    // MARK: - Preview
    var previewLayer: AVCaptureVideoPreviewLayer {
        AVCaptureVideoPreviewLayer(session: captureSession)
    }

    // MARK: - Frame Processing
    var frameProcessor: ((CMSampleBuffer) -> Void)?

    // MARK: - Initialization
    override init() {
        super.init()
        discoverFrontCamera()
    }

    // MARK: - Camera Discovery
    private func discoverFrontCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Try TrueDepth camera first (iPhone 17 Pro front camera)
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera
            ]

            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .front
            )

            // Get the best front camera available
            self.frontCamera = discoverySession.devices.first

            if let camera = self.frontCamera {
                print("Found front camera: \(camera.localizedName)")
                self.enumerateFormats(for: camera)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "No front camera found"
                }
            }
        }
    }

    // MARK: - Format Enumeration
    private func enumerateFormats(for device: AVCaptureDevice) {
        var formats: [DeviceFormatOption] = []
        var seenResolutions: Set<String> = []

        for format in device.formats {
            guard let formatDescription = format.formatDescription as CMFormatDescription? else {
                continue
            }

            // Get dimensions
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

            // Get clean aperture if available
            let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(
                formatDescription,
                originIsAtTopLeft: true
            )

            let cleanWidth = Int(cleanAperture.width)
            let cleanHeight = Int(cleanAperture.height)

            // Skip if we've seen this resolution already
            let resKey = "\(cleanWidth)x\(cleanHeight)"
            if seenResolutions.contains(resKey) {
                continue
            }
            seenResolutions.insert(resKey)

            // Get FPS range
            let ranges = format.videoSupportedFrameRateRanges
            let maxFPS = ranges.map { $0.maxFrameRate }.max() ?? 30.0
            let minFPS = ranges.map { $0.minFrameRate }.min() ?? 1.0

            // Check if square (within 1% tolerance)
            let aspectRatio = Double(cleanWidth) / Double(cleanHeight)
            let isSquare = abs(aspectRatio - 1.0) < 0.01

            // Create format option
            let option = DeviceFormatOption(
                format: format,
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                cleanWidth: cleanWidth,
                cleanHeight: cleanHeight,
                isSquareFormat: isSquare,
                maxFPS: maxFPS,
                minFPS: minFPS,
                formatDescription: format.description
            )

            formats.append(option)
        }

        // Sort: square formats first, then by megapixels
        formats.sort { lhs, rhs in
            if lhs.isSquareFormat != rhs.isSquareFormat {
                return lhs.isSquareFormat
            }
            return lhs.megapixels > rhs.megapixels
        }

        DispatchQueue.main.async {
            self.availableFormats = formats

            // Select the largest square format by default
            if let bestSquare = formats.first(where: { $0.isSquareFormat }) {
                self.selectedFormat = bestSquare
                print("Selected default format: \(bestSquare.displayName)")
            } else if let first = formats.first {
                self.selectedFormat = first
                print("No square format found, using: \(first.displayName)")
            }
        }
    }

    // MARK: - Format Switching
    func selectFormat(_ format: DeviceFormatOption) {
        guard format != selectedFormat else { return }

        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.frontCamera else { return }

            do {
                // Stop session for reconfiguration
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }

                self.captureSession.beginConfiguration()
                defer { self.captureSession.commitConfiguration() }

                // Lock device for configuration
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                // Set active format
                device.activeFormat = format.format

                // Set frame rate to max supported
                let targetFPS = min(format.maxFPS, 30.0)
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration

                // Session preset must be inputPriority when using activeFormat
                self.captureSession.sessionPreset = .inputPriority

                DispatchQueue.main.async {
                    self.selectedFormat = format
                    print("Switched to format: \(format.displayName)")
                }

                // Restart session
                if self.isSessionRunning {
                    self.captureSession.startRunning()
                }

            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to switch format: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Session Configuration
    func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.frontCamera else { return }

            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }

            // Remove existing inputs/outputs
            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            self.captureSession.outputs.forEach { self.captureSession.removeOutput($0) }

            // Add camera input
            guard let cameraInput = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to create camera input"
                }
                return
            }

            if self.captureSession.canAddInput(cameraInput) {
                self.captureSession.addInput(cameraInput)
            }

            // Configure video data output for BGRA
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: self.videoDataQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true

            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
                self.videoDataOutput = videoOutput
            }

            // Configure connection
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = true // Mirror for selfie
            }

            // Apply selected format if available
            if let format = self.selectedFormat {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = format.format
                    self.captureSession.sessionPreset = .inputPriority
                    device.unlockForConfiguration()
                } catch {
                    print("Failed to set initial format: \(error)")
                }
            }
        }
    }

    // MARK: - Session Control
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()

                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()

                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension FrontCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Forward to processor if set
        frameProcessor?(sampleBuffer)
    }
}