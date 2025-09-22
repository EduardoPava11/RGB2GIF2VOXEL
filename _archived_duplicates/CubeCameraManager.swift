// Updated CubeCameraManager with all enhancements integrated
// Replace the existing CubeCameraManager.swift with this version
//
// Capture Profile: "Front-Max-Square (Preview+Analysis)"
// -------------------------------------------------------
// Device: Front TrueDepth camera (iPhone 17 Pro preferred), fallback to front wide
// Format: Largest 1:1 clean-aperture format, or largest format with center crop
// Preview: AVCaptureVideoPreviewLayer (mirrored for front camera)
// Pixel Format: BGRA for simplicity (TODO: YUV 420f for performance)
// Processing: Square guarantee → N×N downscale → quantize → N frames → N×N×N tensor
// Export: GIF89a with ≤256 colors per frame

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Combine

// MARK: - Camera Format Information

struct CameraFormatInfo {
    let width: Int
    let height: Int
    let cleanApertureWidth: Int
    let cleanApertureHeight: Int
    let isNativeSquare: Bool
    let needsCrop: Bool
    let fps: Double

    var isSquare: Bool {
        return width == height
    }

    var displayText: String {
        if isNativeSquare {
            return "\(cleanApertureWidth)×\(cleanApertureHeight) • Native 1:1"
        } else {
            return "\(width)×\(height) • Crop to 1:1"
        }
    }
}

// MARK: - Cube Camera Manager

@MainActor
class CubeCameraManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var currentFormat: CameraFormatInfo?
    @Published var isCapturing: Bool = false
    @Published var currentFPS: Double = 0
    @Published var captureElapsedTime: Double = 0
    @Published var estimatedCaptureTime: Double = 0
    @Published private(set) var clipController: CubeClipController

    // MARK: - Session
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.yingif.cube.session")
    private let videoDataQueue = DispatchQueue(label: "com.yingif.cube.videodata", qos: .userInitiated)

    // MARK: - Camera
    private var frontCamera: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var needsSquareCrop: Bool = false

    // MARK: - Processing
    private let rustProcessor = YinGifProcessor()
    private var pyramidLevel: Int = CubePolicy.defaultLevel
    private var paletteSize: Int = 256

    // MARK: - Capture Timing
    private var captureStartTime: CFTimeInterval = 0
    private var captureTimer: Timer?

    // MARK: - FPS Tracking
    private var frameTimestamps: [Double] = []
    private let maxTimestamps = 30

    // MARK: - Initialization

    override init() {
        self.clipController = CubeClipController(
            sideN: CubePolicy.defaultLevel,
            paletteSize: 256
        )
        super.init()
    }

    // MARK: - Session Setup

    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            // 1. Discover front camera (TrueDepth preferred)
            guard let camera = self.discoverFrontCamera() else {
                print("❌ No front camera available")
                return
            }

            self.frontCamera = camera

            // 2. Add camera input
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                } else {
                    print("❌ Cannot add camera input")
                    return
                }
            } catch {
                print("❌ Failed to create camera input: \(error)")
                return
            }

            // 3. Find best format (native square or max resolution)
            guard let (format, formatInfo) = self.bestSquareOrMaxFormat(for: camera) else {
                print("❌ No suitable format found")
                return
            }

            // 4. Configure format
            do {
                try self.configureFormat(format, on: camera, info: formatInfo)
                self.session.sessionPreset = .inputPriority  // Required when setting activeFormat
            } catch {
                print("❌ Failed to configure format: \(error)")
            }

            // 5. Add BGRA video output
            let output = self.configureBGRAOutput()
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                self.videoOutput = output

                // Configure connection
                if let connection = output.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    connection.isVideoMirrored = true  // Mirror for selfie
                    connection.preferredVideoStabilizationMode = .off  // Deterministic timing
                }
            }

            print("✅ Camera session configured successfully")
        }
    }

    // MARK: - Camera Discovery

    private func discoverFrontCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTrueDepthCamera,  // iPhone X+ (best quality)
                .builtInWideAngleCamera   // Older devices fallback
            ],
            mediaType: .video,
            position: .front
        )

        guard let device = discoverySession.devices.first else {
            return nil
        }

        print("✅ Found front camera: \(device.localizedName)")
        return device
    }

    // MARK: - Format Selection

    private func bestSquareOrMaxFormat(for device: AVCaptureDevice) -> (AVCaptureDevice.Format, CameraFormatInfo)? {
        var nativeSquareFormats: [(AVCaptureDevice.Format, CameraFormatInfo)] = []
        var nonSquareFormats: [(AVCaptureDevice.Format, CameraFormatInfo)] = []

        for format in device.formats {
            guard let desc = format.formatDescription as CMFormatDescription? else { continue }

            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(desc, originIsAtTopLeft: true)

            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            let cleanWidth = Int(cleanAperture.size.width)
            let cleanHeight = Int(cleanAperture.size.height)

            let aspectRatio = Double(cleanWidth) / Double(cleanHeight)
            let isNativeSquare = abs(aspectRatio - 1.0) < 0.02  // 2% tolerance for iPhone 17 Pro variations

            let maxFPS = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30.0

            let info = CameraFormatInfo(
                width: width,
                height: height,
                cleanApertureWidth: cleanWidth,
                cleanApertureHeight: cleanHeight,
                isNativeSquare: isNativeSquare,
                needsCrop: !isNativeSquare,
                fps: maxFPS
            )

            if isNativeSquare {
                nativeSquareFormats.append((format, info))
            } else {
                nonSquareFormats.append((format, info))
            }
        }

        // Prefer largest native square format
        if let best = nativeSquareFormats.max(by: { a, b in
            (a.1.cleanApertureWidth * a.1.cleanApertureHeight) <
            (b.1.cleanApertureWidth * b.1.cleanApertureHeight)
        }) {
            print("✅ Found native 1:1 format: \(best.1.cleanApertureWidth)×\(best.1.cleanApertureHeight)")
            return best
        }

        // Fallback to highest resolution for cropping
        if let best = nonSquareFormats.max(by: { a, b in
            (a.1.width * a.1.height) < (b.1.width * b.1.height)
        }) {
            print("⚠️ Will crop from \(best.1.width)×\(best.1.height) to square")
            return best
        }

        return nil
    }

    // MARK: - Format Configuration

    private func configureFormat(_ format: AVCaptureDevice.Format, on device: AVCaptureDevice, info: CameraFormatInfo) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = format
        self.needsSquareCrop = info.needsCrop

        // Update published format info
        Task { @MainActor in
            self.currentFormat = info
        }

        // Set frame rate (30fps or max available)
        let targetFPS: Double = 30.0
        for range in format.videoSupportedFrameRateRanges {
            if range.minFrameRate <= targetFPS && targetFPS <= range.maxFrameRate {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                print("✅ Frame rate set to \(targetFPS) fps")
                break
            }
        }

        // Enable low light boost if available
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
    }

    // MARK: - BGRA Output Configuration

    private func configureBGRAOutput() -> AVCaptureVideoDataOutput {
        let output = AVCaptureVideoDataOutput()

        // BGRA pixel format (converted from native YUV by AVFoundation)
        // TODO: Performance path - use kCVPixelFormatType_420YpCbCr8BiPlanarFullRange (420f)
        //       for native format and convert YUV→RGB in vImage/Metal/Rust to reduce overhead
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        output.setSampleBufferDelegate(self, queue: videoDataQueue)
        output.alwaysDiscardsLateVideoFrames = true  // Drop late frames for better throughput

        print("✅ BGRA output configured (converted from native format)")
        return output
    }

    // MARK: - Stride Compaction Helper

    /// Compacts BGRA pixel data to remove row padding (stride)
    /// CVPixelBuffer often has bytesPerRow > width*4 for alignment (typically 16-pixel boundaries)
    /// This creates tightly packed data for Rust FFI which expects width*height*4 bytes
    private func extractCompactBGRA(from buffer: CVPixelBuffer,
                                   width: Int,
                                   height: Int,
                                   bytesPerRow: Int,
                                   baseAddress: UnsafeRawPointer) -> Data {
        // Check if already tightly packed
        if bytesPerRow == width * 4 {
            // No padding, can use directly
            return Data(bytes: baseAddress, count: width * height * 4)
        } else {
            // Has padding, must compact row by row
            var compactData = Data(capacity: width * height * 4)
            for row in 0..<height {
                let rowStart = baseAddress + (row * bytesPerRow)
                compactData.append(Data(bytes: rowStart, count: width * 4))
            }
            print("📦 Compacted BGRA: \(bytesPerRow) → \(width * 4) bytes/row")
            return compactData
        }
    }

    // MARK: - Center Crop Helper

    private func centerCropToSquare(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if width == height {
            return pixelBuffer  // Already square
        }

        let targetSize = min(width, height)
        let xOffset = (width - targetSize) / 2
        let yOffset = (height - targetSize) / 2

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetSize, targetSize,
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return nil
        }

        // Copy center region
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)

        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer),
              let dstBase = CVPixelBufferGetBaseAddress(output) else {
            return nil
        }

        let srcPtr = srcBase.assumingMemoryBound(to: UInt8.self)
        let dstPtr = dstBase.assumingMemoryBound(to: UInt8.self)

        for y in 0..<targetSize {
            let srcRow = yOffset + y
            let srcOffset = srcRow * srcBytesPerRow + xOffset * 4
            let dstOffset = y * dstBytesPerRow
            memcpy(dstPtr + dstOffset, srcPtr + srcOffset, targetSize * 4)
        }

        return output
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Capture Control

    func startCapture() {
        clipController.startCapture()
        isCapturing = true
        frameTimestamps.removeAll()
        
        // Setup capture timing for 256³ (8.5 seconds at 30fps)
        captureStartTime = CACurrentMediaTime()
        estimatedCaptureTime = Double(pyramidLevel) / 30.0 // N frames at 30fps
        captureElapsedTime = 0
        
        // Start capture timer for UI updates
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCaptureProgress()
            }
        }
        
        print("🎬 Starting capture: \(pyramidLevel) frames over \(String(format: "%.1f", estimatedCaptureTime))s")
    }

    func stopCapture() {
        clipController.stopCapture()
        isCapturing = false
        
        // Stop capture timer
        captureTimer?.invalidate()
        captureTimer = nil
        captureElapsedTime = 0
        
        let actualDuration = CACurrentMediaTime() - captureStartTime
        print("✅ Capture complete: \(clipController.framesCaptured) frames in \(String(format: "%.2f", actualDuration))s")
    }
    
    private func updateCaptureProgress() {
        captureElapsedTime = CACurrentMediaTime() - captureStartTime
        
        // Auto-stop if capture takes too long (safety mechanism)
        if captureElapsedTime > estimatedCaptureTime * 1.5 {
            print("⚠️ Capture timeout - stopping")
            stopCapture()
        }
    }

    func reset() {
        clipController = CubeClipController(sideN: pyramidLevel, paletteSize: paletteSize)
        isCapturing = false
    }

    // MARK: - Configuration Updates

    func updatePyramidLevel(_ level: Int) {
        pyramidLevel = level
        clipController = CubeClipController(sideN: level, paletteSize: paletteSize)
    }

    func updatePaletteSize(_ size: Int) {
        paletteSize = size
        clipController = CubeClipController(sideN: pyramidLevel, paletteSize: size)
    }

    // MARK: - FPS Tracking

    private func updateFPS() {
        let now = CACurrentMediaTime()
        frameTimestamps.append(now)
        while frameTimestamps.count > maxTimestamps {
            frameTimestamps.removeFirst()
        }
        if frameTimestamps.count >= 2 {
            let duration = frameTimestamps.last! - frameTimestamps.first!
            let fps = Double(frameTimestamps.count - 1) / duration
            Task { @MainActor in
                self.currentFPS = fps
            }
        }
    }
}

// MARK: - Video Data Output Delegate

extension CubeCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {

        updateFPS()

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard clipController.shouldAcceptNextFrame(timestamp: timestamp) else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Apply center crop if needed
        let squareBuffer: CVPixelBuffer
        if needsSquareCrop {
            guard let cropped = centerCropToSquare(pixelBuffer) else { return }
            squareBuffer = cropped
        } else {
            squareBuffer = pixelBuffer
        }

        // Extract BGRA data
        CVPixelBufferLockBaseAddress(squareBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(squareBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(squareBuffer)
        let height = CVPixelBufferGetHeight(squareBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(squareBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(squareBuffer) else { return }

        // Extract compacted BGRA data (remove stride padding for Rust FFI)
        let bgraData = extractCompactBGRA(
            from: squareBuffer,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            baseAddress: baseAddress
        )

        // Process in Rust (downsize + quantize)
        Task.detached(priority: .userInitiated) { [pyramidLevel, paletteSize, clipController, rustProcessor] in
            do {
                let frameIndex = await clipController.framesCaptured
                let processedFrame = try await rustProcessor.processFrameAsync(
                    bgraData: bgraData,
                    width: width,
                    height: height,
                    targetSize: pyramidLevel,
                    paletteSize: paletteSize
                )

                // Create new frame with correct index
                let quantizedFrame = QuantizedFrame(
                    index: frameIndex,
                    width: processedFrame.width,
                    height: processedFrame.height,
                    indices: processedFrame.indices,
                    palette: processedFrame.palette
                )

                await MainActor.run {
                    let isFinal = clipController.ingestFrame(quantizedFrame)
                    if isFinal {
                        _ = clipController.buildCubeTensor()
                    }
                }
            } catch {
                print("Frame processing error: \(error)")
            }
        }
    }
}