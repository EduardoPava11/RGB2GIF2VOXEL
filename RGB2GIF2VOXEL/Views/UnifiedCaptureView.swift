//
//  UnifiedCaptureView.swift
//  RGB2GIF2VOXEL
//
//  Single, correct capture flow with proper frame handling
//

import SwiftUI
import AVFoundation
import Combine
import os

public struct UnifiedCaptureView: View {
    @StateObject private var viewModel = UnifiedCaptureViewModel()
    @State private var showingVoxelView = false

    public init() {}

    public var body: some View {
        ZStack {
            // Camera preview
            UnifiedCameraPreview(session: viewModel.session)
                .ignoresSafeArea()

            // UI overlay
            VStack {
                // Header with status
                statusHeader

                Spacer()

                // Capture controls
                captureControls

                // Bottom info and camera toggle
                VStack {
                    bottomInfo
                    cameraToggleButton
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.setupCamera()
        }
        .sheet(isPresented: $showingVoxelView) {
            if let tensorData = viewModel.tensorData {
                VoxelTensorView(tensorData: tensorData, gifData: viewModel.gifData)
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 8) {
            Text("RGB → GIF → VOXEL")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            if viewModel.isProcessing {
                Text(viewModel.processingMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Text("128×128×128 Tensor Pipeline")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.top, 60)
    }

    private var captureControls: some View {
        VStack(spacing: 20) {
            if viewModel.isCapturing {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: viewModel.captureProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: viewModel.captureProgress)

                    VStack {
                        Text("\(viewModel.framesCaptured)")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                        Text("of 128")
                            .font(.caption)
                            .opacity(0.6)
                    }
                    .foregroundColor(.white)
                }
            } else if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if viewModel.tensorData != nil {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Button(action: { showingVoxelView = true }) {
                        Label("View Voxel Cube", systemImage: "cube.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                Capsule()
                                    .fill(Color.purple)
                            )
                    }
                }
            } else {
                // Capture button
                Button(action: { Task { await viewModel.startCapture() } }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)

                        Image(systemName: "camera.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(.bottom, 40)
    }

    private var bottomInfo: some View {
        VStack(spacing: 4) {
            if let tensorInfo = viewModel.tensorInfo {
                Text(tensorInfo)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.green)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .frame(height: 60)
    }

    private var cameraToggleButton: some View {
        HStack {
            Spacer()

            Button(action: {
                Task { await viewModel.toggleCamera() }
            }) {
                Image(systemName: "camera.rotate")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .disabled(viewModel.isCapturing || viewModel.isProcessing)
            .opacity((viewModel.isCapturing || viewModel.isProcessing) ? 0.3 : 1.0)

            Spacer()
        }
        .padding(.bottom, 30)
    }
}

// MARK: - View Model

@MainActor
class UnifiedCaptureViewModel: NSObject, ObservableObject {
    // Published properties
    @Published var framesCaptured = 0
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var captureProgress: Double = 0
    @Published var processingMessage = ""
    @Published var tensorInfo: String?
    @Published var errorMessage: String?
    @Published var tensorData: Data?
    @Published var gifData: Data?

    // Camera
    let session = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentInput: AVCaptureDeviceInput?
    private var cameraPosition: AVCaptureDevice.Position = .back
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let processingQueue = DispatchQueue(label: "frame.processing", qos: .userInitiated)

    // Frame processing
    private let processor = CanonicalFrameProcessor()
    private var capturedFrames: [Data] = []
    private let targetFrameCount = 128

    // Logging
    private let logger = Logger(subsystem: "com.rgb2gif2voxel", category: "UnifiedCapture")

    override init() {
        super.init()
    }

    func setupCamera() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.configureSession()
                continuation.resume()
            }
        }
        session.startRunning()
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720  // Standard HD for consistent input

        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            logger.error("Failed to setup camera input")
            session.commitConfiguration()
            return
        }
        currentInput = input
        session.addInput(input)

        // Configure video output
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: processingQueue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            logger.error("Failed to add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        videoOutput = output

        // Configure connection with proper orientation
        if let connection = output.connection(with: .video) {
            // Set rotation angle based on device orientation
            // For portrait mode on iPhone, we need 90 degree rotation
            connection.videoRotationAngle = 90
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (cameraPosition == .front)
            }
        }

        session.commitConfiguration()
        logger.info("Camera configured successfully")
    }

    func startCapture() async {
        framesCaptured = 0
        capturedFrames = []
        isCapturing = true
        captureProgress = 0
        errorMessage = nil
        tensorInfo = nil
    }

    func toggleCamera() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                self.session.beginConfiguration()

                // Remove current input
                if let currentInput = self.currentInput {
                    self.session.removeInput(currentInput)
                }

                // Toggle position
                self.cameraPosition = self.cameraPosition == .back ? .front : .back

                // Add new input
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.session.canAddInput(input) else {
                    self.logger.error("Failed to switch camera")
                    self.session.commitConfiguration()
                    continuation.resume()
                    return
                }

                self.session.addInput(input)
                self.currentInput = input

                // Update connection with proper orientation
                if let connection = self.videoOutput?.connection(with: .video) {
                    // iPhone camera needs 90 degree rotation for portrait orientation
                    connection.videoRotationAngle = 90
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = (self.cameraPosition == .front)
                    }
                }

                self.session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    private func processFrames() async {
        isCapturing = false
        isProcessing = true
        processingMessage = "Building tensor..."

        do {
            // Build 128×128×128×4 tensor
            guard let tensorData = processor.buildTensor(from: capturedFrames) else {
                throw ProcessingError.tensorBuildFailed
            }

            self.tensorData = tensorData

            // Save to disk
            if let url = processor.saveTensor(tensorData) {
                let sizeInMB = Double(tensorData.count) / 1024 / 1024
                tensorInfo = String(format: "Tensor saved: %.2f MB at %@", sizeInMB, url.lastPathComponent)
            }

            processingMessage = "Creating GIF..."

            // Create GIF from frames
            let gifBuilder = GIFBuilderImageIO()
            var images: [UIImage] = []
            for frameData in capturedFrames {
                if let image = processor.createUIImage(from: frameData) {
                    images.append(image)
                }
            }

            let config = GIFBuilderImageIO.Config(
                width: CanonicalFrameProcessor.frameSize,
                height: CanonicalFrameProcessor.frameSize,
                fps: 30,
                loopCount: 0
            )

            if let gif = gifBuilder.buildGIF(images: images, config: config) {
                self.gifData = gif
                logger.info("Created GIF: \(gif.count) bytes")
            }

            isProcessing = false
            processingMessage = ""

        } catch {
            logger.error("Processing failed: \(error)")
            errorMessage = "Processing failed: \(error.localizedDescription)"
            isProcessing = false
        }
    }
}

// MARK: - Camera Delegate

extension UnifiedCaptureViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {

        guard isCapturing,
              framesCaptured < targetFrameCount,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Process frame to canonical 128×128×4 format
        // Orientation is already handled at the connection level
        guard let frameData = processor.processFrame(pixelBuffer) else {
            logger.warning("Failed to process frame \(self.framesCaptured)")
            return
        }

        // Validate frame size
        guard frameData.count == CanonicalFrameProcessor.bytesPerFrame else {
            logger.error("Invalid frame size: \(frameData.count)")
            return
        }

        capturedFrames.append(frameData)

        Task { @MainActor in
            framesCaptured += 1
            captureProgress = Double(framesCaptured) / Double(targetFrameCount)

            if framesCaptured >= targetFrameCount {
                await processFrames()
            }
        }
    }
}

// MARK: - Camera Preview

struct UnifiedCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Error Types

enum ProcessingError: LocalizedError {
    case tensorBuildFailed
    case gifCreationFailed

    var errorDescription: String? {
        switch self {
        case .tensorBuildFailed:
            return "Failed to build voxel tensor"
        case .gifCreationFailed:
            return "Failed to create GIF"
        }
    }
}