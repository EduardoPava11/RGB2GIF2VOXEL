//
//  Complete128CaptureView.swift
//  RGB2GIF2VOXEL
//
//  Complete 128 frame capture with dual path processing and voxel generation
//

import SwiftUI
import AVFoundation
import Photos
import Combine

/// Complete view implementing N=128 capture with Rust/Swift paths and voxel generation
public struct Complete128CaptureView: View {

    @StateObject private var viewModel = CaptureViewModel()
    @StateObject private var optimizedPipeline = OptimizedGIF128Pipeline()
    @State private var selectedPath: ProcessingPath = .rustFFI
    @State private var showingVoxels = false
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        ZStack {
            // Camera preview
            if !showingVoxels {
                CameraPreviewRepresentable(session: viewModel.cameraSession)
                    .ignoresSafeArea()

                captureInterface
            } else if let tensorData = viewModel.lastTensorData,
                      let gifData = viewModel.lastGIFData {
                // Voxel visualization
                VoxelVisualizationScreen(
                    gifData: gifData,
                    tensorData: tensorData
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))

                backButton
            }
        }
        .task {
            await viewModel.setupCamera()
        }
    }

    private var captureInterface: some View {
        VStack {
            // Header
            headerView

            Spacer()

            // Processing path selector
            if !viewModel.isCapturing && !viewModel.isProcessing {
                pathSelector
            }

            // Progress view
            if viewModel.isCapturing || viewModel.isProcessing {
                progressView
            }

            // Capture button
            if !viewModel.isProcessing {
                captureButton
            }

            Spacer()
                .frame(height: 100)
        }
    }

    private var headerView: some View {
        VStack(spacing: 4) {
            Text("N=128 Optimal Capture")
                .font(.title2)
                .fontWeight(.bold)

            Text("128 frames → 128×128 → GIF89a + Voxels")
                .font(.caption)
                .opacity(0.8)
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .padding(.top, 60)
    }

    private var pathSelector: some View {
        HStack(spacing: 20) {
            ForEach(ProcessingPath.allCases, id: \.self) { path in
                Button(action: {
                    selectedPath = path
                    HapticFeedback.selection()
                }) {
                    VStack {
                        Image(systemName: path.icon)
                            .font(.title2)
                        Text(path.viewDisplayName)
                            .font(.caption)
                    }
                    .foregroundColor(selectedPath == path ? .white : .gray)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedPath == path ? path.color : Color.gray.opacity(0.2))
                    )
                }
            }
        }
        .padding()
    }

    private var progressView: some View {
        VStack(spacing: 12) {
            if viewModel.isCapturing {
                Text("Capturing: \(viewModel.capturedFrames)/128")
                    .font(.headline)
                    .foregroundColor(.white)
            } else {
                Text(viewModel.currentStage)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .frame(width: 250)

            if viewModel.isProcessing {
                Text("Using \(selectedPath.viewDisplayName)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }

    private var captureButton: some View {
        Button(action: {
            if viewModel.isCapturing {
                viewModel.stopCapture()
            } else {
                Task {
                    await viewModel.startCapture(using: selectedPath)
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: viewModel.isCapturing ? [.red, .orange] : [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                if viewModel.isCapturing {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .cornerRadius(5)
                } else {
                    VStack(spacing: 2) {
                        Text("128")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                        Text("CAPTURE")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .scaleEffect(viewModel.isCapturing ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isCapturing)
    }

    private var backButton: some View {
        VStack {
            HStack {
                Button(action: {
                    withAnimation {
                        showingVoxels = false
                        viewModel.reset()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("New Capture")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                }
                .padding()

                Spacer()
            }
            Spacer()
        }
    }
}

// MARK: - View Model

@MainActor
class CaptureViewModel: ObservableObject {
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var capturedFrames = 0
    @Published var progress: Double = 0
    @Published var currentStage = ""
    @Published var lastGIFData: Data?
    @Published var lastTensorData: Data?

    let cameraSession = AVCaptureSession()
    private var cameraManager: CubeCameraManagerOptimized?
    private var processor: CubeProcessor?
    private let targetFrameCount = 128
    private let targetSize = 128
    private var capturedFrameData: [Data] = []

    func setupCamera() async {
        // Initialize camera manager if needed
        if cameraManager == nil {
            cameraManager = CubeCameraManagerOptimized()
        }

        // Initialize processor if needed
        if processor == nil {
            processor = await CubeProcessor()
        }

        guard let manager = cameraManager else { return }

        await withCheckedContinuation { continuation in
            manager.sessionQueue.async { [weak self, weak manager] in
                guard let self = self, let manager = manager else {
                    continuation.resume()
                    return
                }

                manager.setupSession()
                self.cameraSession.inputs.forEach { self.cameraSession.removeInput($0) }
                self.cameraSession.outputs.forEach { self.cameraSession.removeOutput($0) }

                // Copy inputs/outputs from manager's session
                manager.session.inputs.forEach { self.cameraSession.addInput($0) }
                manager.session.outputs.forEach { self.cameraSession.addOutput($0) }

                self.cameraSession.startRunning()
                continuation.resume()
            }
        }
    }

    private var currentProcessingPath: ProcessingPath = .rustFFI

    func startCapture(using path: ProcessingPath) async {
        currentProcessingPath = path
        isCapturing = true
        capturedFrames = 0
        capturedFrameData.removeAll()
        capturedFrameData.reserveCapacity(targetFrameCount)
        currentStage = "Capturing frames..."

        // Set up frame capture callback
        cameraManager?.frameProcessor = { [weak self] pixelBuffer in
            Task { @MainActor in
                await self?.processIncomingFrame(pixelBuffer)
            }
        }

        cameraManager?.startCapture()
    }

    func stopCapture() {
        isCapturing = false
        cameraManager?.stopCapture()
        cameraManager?.frameProcessor = nil
    }

    private func processIncomingFrame(_ pixelBuffer: CVPixelBuffer) async {
        guard isCapturing else { return }
        guard capturedFrameData.count < targetFrameCount else {
            // We have enough frames
            stopCapture()
            Task {
                await processFrames(path: currentProcessingPath)
            }
            return
        }

        // Extract BGRA data
        let bgraData = extractBGRAData(from: pixelBuffer)
        capturedFrameData.append(bgraData)

        capturedFrames = capturedFrameData.count
        progress = Double(capturedFrames) / Double(targetFrameCount)
    }

    private func processFrames(path: ProcessingPath) async {
        isProcessing = true

        do {
            // Step 1: Downsample
            currentStage = "Downsampling to 128×128..."
            progress = 0.2

            let downsampledFrames = try await VImageDownsampler.batchDownsample(
                capturedFrameData,
                from: 1080,  // Capture size
                to: targetSize
            )

            progress = 0.4

            // Step 2: Process with selected path
            if path == .rustFFI {
                currentStage = "🦀 Processing with Rust..."
                let result = try await processWithRust(downsampledFrames)
                lastGIFData = result.gifData
                lastTensorData = result.tensorData ?? createTensorFromFrames(downsampledFrames)
            } else {
                currentStage = "🍎 Processing with Swift..."
                let result = try await processWithSwift(downsampledFrames)
                lastGIFData = result.gifData
                lastTensorData = createTensorFromFrames(downsampledFrames)
            }

            progress = 0.8

            // Step 3: Save GIF
            currentStage = "Saving GIF..."
            if let gifData = lastGIFData {
                await saveGIF(gifData)
            }

            progress = 1.0
            currentStage = "Complete! Tap to view voxels"

        } catch {
            currentStage = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func processWithRust(_ frames: [Data]) async throws -> (gifData: Data, tensorData: Data?) {
        let processor = RustProcessor()
        processor.setIncludeTensor(true)  // Enable voxel generation

        guard let result = await processor.processFramesToGIF(
            frames: frames,
            width: targetSize,
            height: targetSize,
            includeTensor: true
        ) else {
            throw PipelineError.processingFailed("FFI error: code -1")
        }

        return (result.gifData, result.tensorData)
    }

    private func processWithSwift(_ frames: [Data]) async throws -> (gifData: Data, tensorData: Data?) {
        // Use the new OptimizedGIF128Pipeline for high-quality GIF generation
        // This implements STBN 3D dithering, complementary colors, and Wu quantization

        // Convert frames to the format expected by the pipeline
        var frameBuffers: [CVPixelBuffer] = []
        for frameData in frames {
            if let buffer = createPixelBufferFromData(frameData, width: targetSize, height: targetSize) {
                frameBuffers.append(buffer)
            }
        }

        // Process using the optimized pipeline
        let pipeline = OptimizedGIF128Pipeline()
        let result = try await pipeline.process(frames: frameBuffers)

        // The pipeline returns high-quality GIF with complementary color patterns
        return (result.gifData, result.tensorData)
    }

    private func createPixelBufferFromData(_ data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                           kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            data.withUnsafeBytes { bytes in
                memcpy(baseAddress, bytes.baseAddress, min(data.count, width * height * 4))
            }
        }

        return buffer
    }

    private func createTensorFromFrames(_ frames: [Data]) -> Data {
        // Create 128×128×128 RGBA tensor
        var tensorData = Data(capacity: targetSize * targetSize * targetFrameCount * 4)

        for i in 0..<targetFrameCount {
            if i < frames.count {
                tensorData.append(frames[i])
            } else {
                // Pad with empty frames if needed
                let emptyFrame = Data(repeating: 0, count: targetSize * targetSize * 4)
                tensorData.append(emptyFrame)
            }
        }

        return tensorData
    }

    private func extractBGRAData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Data()
        }

        // Center crop to square
        let squareSize = min(width, height)
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        var croppedData = Data(capacity: squareSize * squareSize * 4)
        let srcPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for row in 0..<squareSize {
            let srcRow = srcPtr.advanced(by: (row + yOffset) * bytesPerRow + xOffset * 4)
            croppedData.append(srcRow, count: squareSize * 4)
        }

        return croppedData
    }

    private func saveGIF(_ data: Data) async {
        // Save to documents
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let gifPath = documentsPath.appendingPathComponent("GIFs")
        try? FileManager.default.createDirectory(
            at: gifPath,
            withIntermediateDirectories: true
        )

        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = gifPath.appendingPathComponent("n128_\(timestamp).gif")
        try? data.write(to: outputURL)

        // Save to Photos
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        if status == .authorized {
            try? await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    func reset() {
        capturedFrameData.removeAll()
        capturedFrames = 0
        progress = 0
        currentStage = ""
        lastGIFData = nil
        lastTensorData = nil
    }
}

// MARK: - Supporting Types

// ProcessingPath is imported from ProcessingTypes.swift
// Adding extension for view-specific properties
extension ProcessingPath {
    var icon: String {
        switch self {
        case .rustFFI: return "cube.fill"
        case .swift: return "swift"
        }
    }

    var color: Color {
        switch self {
        case .rustFFI: return .orange
        case .swift: return .blue
        }
    }

    // Map display names for this view
    var viewDisplayName: String {
        switch self {
        case .rustFFI: return "Rust + Voxels"
        case .swift: return "Swift"
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.layer.setValue(previewLayer, forKey: "previewLayer")

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.value(forKey: "previewLayer") as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Haptic Feedback

struct HapticFeedback {
    static func selection() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Preview

struct Complete128CaptureView_Previews: PreviewProvider {
    static var previews: some View {
        Complete128CaptureView()
    }
}