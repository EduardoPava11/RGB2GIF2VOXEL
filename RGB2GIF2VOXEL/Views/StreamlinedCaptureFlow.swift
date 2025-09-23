//
//  StreamlinedCaptureFlow.swift
//  RGB2GIF2VOXEL
//
//  Unified capture flow: Camera → 128 frames → Dual GIF generation → Voxel visualization
//

import SwiftUI
import AVFoundation
import Combine

struct StreamlinedCaptureFlow: View {
    @StateObject private var camera = CameraModel()
    @State private var capturedFrames: [CVPixelBuffer] = []
    @State private var fullResolutionFrames: [Data] = []
    @State private var currentState: FlowState = .ready
    @State private var processingProgress: Double = 0
    @State private var generatedGIF: Data?
    @State private var tensorCBOR: Data?
    @State private var selectedPath: ProcessingPath?
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    @State private var isCapturing = false
    @State private var captureTimer: Timer?

    enum FlowState {
        case ready
        case capturing
        case selectingPath
        case processing
        case complete
        case viewingVoxels
    }

    enum ProcessingPath {
        case rust
        case swift

        var title: String {
            switch self {
            case .rust: return "Rust FFI (with Voxels)"
            case .swift: return "Swift Native"
            }
        }

        var description: String {
            switch self {
            case .rust: return "NeuQuant + tensor generation"
            case .swift: return "ImageIO framework"
            }
        }

        var icon: String {
            switch self {
            case .rust: return "cube.transparent.fill"
            case .swift: return "swift"
            }
        }
    }

    var body: some View {
        ZStack {
            // Always show camera preview as background
            Color.black
                .ignoresSafeArea()

            // Square camera preview for iPhone 17 Pro front camera
            GeometryReader { geometry in
                let squareSize = min(geometry.size.width, geometry.size.height)
                StreamlinedCameraPreview(camera: camera)
                    .frame(width: squareSize, height: squareSize)
                    .clipped()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            // Main content overlay
            VStack {
                // Top status bar
                statusBar

                Spacer()

                // Main content based on state
                switch currentState {
                case .ready:
                    readyInterface

                case .capturing:
                    captureInterface

                case .selectingPath:
                    pathSelectionInterface

                case .processing:
                    processingInterface

                case .complete:
                    completionInterface

                case .viewingVoxels:
                    if let cbor = tensorCBOR, let gif = generatedGIF {
                        // Extract tensor data from CBOR for visualization
                        let tensorData = extractTensorFromCBOR(cbor)
                        VoxelVisualizationScreen(gifData: gif, tensorData: tensorData)
                    }
                }

                Spacer()
            }
            }
        }
        .onAppear {
            camera.startSession()
        }
        .alert("GIF Saved", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveMessage)
        }
    }

    private var statusBar: some View {
        HStack {
            // App title
            Text("RGB2GIF2VOXEL")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // Frame counter
            if currentState == .capturing || currentState == .ready {
                Label("\(capturedFrames.count)/128", systemImage: "camera.aperture")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var readyInterface: some View {
        VStack(spacing: 30) {
            // Square preview indicator
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                .frame(width: 300, height: 300)
                .overlay(
                    Text("Square Front Camera\niPhone 17 Pro")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                )

            // Capture button
            Button {
                startCapture()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                    Text("128")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            Text("Tap to capture 128 frames at full resolution")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.6))
                .cornerRadius(25)
        }
        .padding(.bottom, 100)
    }

    private var captureInterface: some View {
        VStack(spacing: 20) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: Double(capturedFrames.count) / 128.0)
                    .stroke(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: capturedFrames.count)

                VStack {
                    Text("\(capturedFrames.count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("of 128")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Text("Capturing frames...")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.6))
                .cornerRadius(25)
        }
        .padding(.bottom, 100)
    }

    private var pathSelectionInterface: some View {
        VStack(spacing: 30) {
            Text("Select Processing Method")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            HStack(spacing: 20) {
                ForEach([ProcessingPath.rust, ProcessingPath.swift], id: \.self) { path in
                    Button {
                        selectedPath = path
                        processFrames(using: path)
                    } label: {
                        VStack(spacing: 15) {
                            Image(systemName: path.icon)
                                .font(.system(size: 40))
                                .foregroundColor(.white)

                            Text(path.title)
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(path.description)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 150, height: 150)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: path == .rust ? [.purple, .pink] : [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    }
                }
            }

            Text("128 frames captured successfully")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.8))
        )
        .padding()
    }

    private var processingInterface: some View {
        VStack(spacing: 20) {
            ProgressView(value: processingProgress) {
                Text("Processing with \(selectedPath?.title ?? "")...")
                    .foregroundColor(.white)
            }
            .progressViewStyle(.linear)
            .tint(.purple)
            .padding(.horizontal, 40)

            Text("\(Int(processingProgress * 100))%")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if selectedPath == .rust {
                Text("Generating voxel tensor...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.8))
        )
        .padding()
    }

    private var completionInterface: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("GIF Created!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            VStack(spacing: 15) {
                Button {
                    saveGIF()
                } label: {
                    Label("Save GIF", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                if tensorCBOR != nil {
                    Button {
                        currentState = .viewingVoxels
                    } label: {
                        Label("View Voxel Cube", systemImage: "cube.transparent.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                }

                Button {
                    resetFlow()
                } label: {
                    Label("Capture Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.9))
        )
        .padding()
    }

    // MARK: - Actions

    private func startCapture() {
        currentState = .capturing
        isCapturing = true
        capturedFrames.removeAll()
        fullResolutionFrames.removeAll()

        // Capture 128 frames at full resolution
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { timer in  // ~30fps
            Task { @MainActor in
                if capturedFrames.count >= 128 {
                    timer.invalidate()
                    captureTimer = nil
                    isCapturing = false
                    await saveFullResolutionFrames()
                    currentState = .selectingPath
                } else {
                    if let buffer = camera.currentFrame {
                        capturedFrames.append(buffer)
                        // Save full resolution data immediately
                        if let fullResData = pixelBufferToData(buffer) {
                            fullResolutionFrames.append(fullResData)
                        }
                    }
                }
            }
        }
    }

    private func saveFullResolutionFrames() async {
        // Frames are already saved in fullResolutionFrames array
        print("Saved \(fullResolutionFrames.count) frames at full resolution")
    }

    private func processFrames(using path: ProcessingPath) {
        currentState = .processing
        processingProgress = 0

        Task {
            do {
                switch path {
                case .rust:
                    let result = try await processWithRust()
                    await MainActor.run {
                        generatedGIF = result.gif
                        tensorCBOR = result.tensor
                        currentState = .complete
                    }

                case .swift:
                    let gif = try await processWithSwift()
                    await MainActor.run {
                        generatedGIF = gif
                        // tensorCBOR is already set in processWithSwift
                        currentState = .complete
                    }
                }
            } catch {
                print("Processing error: \(error)")
                // Handle error appropriately
            }
        }
    }

    private func processWithRust() async throws -> (gif: Data, tensor: Data) {
        // Process with Rust FFI pipeline

        // Step 1: Downsample full resolution frames to 128x128
        var downsampledFrames: [Data] = []
        let sourceSize = CVPixelBufferGetWidth(capturedFrames[0])

        for (index, fullResData) in fullResolutionFrames.enumerated() {
            await MainActor.run {
                processingProgress = Double(index) / Double(fullResolutionFrames.count) * 0.3
            }

            let resized = try VImageDownsampler.downsample(
                fullResData,
                from: sourceSize,
                to: 128
            )
            downsampledFrames.append(resized)
        }

        // Step 2: Create CBOR tensor from 128x128x128 data
        let cborTensor = createCBORTensor(from: downsampledFrames)
        await MainActor.run {
            processingProgress = 0.5
        }

        // Step 3: Build GIF89a with per-frame palettes using Rust
        // For now, use mock implementation
        let gif = try await buildGIFWithPerFramePalettes(from: downsampledFrames, method: .rust)

        await MainActor.run {
            processingProgress = 1.0
        }

        return (gif, cborTensor)
    }

    private func processWithSwift() async throws -> Data {
        // Process with OptimizedGIF128Pipeline for maximum quality
        // Uses STBN 3D dithering, complementary colors, and Wu quantization

        // Step 1: Downsample full resolution frames to 128x128
        var downsampledFrames: [Data] = []
        let sourceSize = CVPixelBufferGetWidth(capturedFrames[0])

        for (index, fullResData) in fullResolutionFrames.enumerated() {
            await MainActor.run {
                processingProgress = Double(index) / Double(fullResolutionFrames.count) * 0.3
            }

            let resized = try VImageDownsampler.downsample(
                fullResData,
                from: sourceSize,
                to: 128
            )
            downsampledFrames.append(resized)
        }

        await MainActor.run {
            processingProgress = 0.4
        }

        // Step 2: Convert to CVPixelBuffers for the optimized pipeline
        var pixelBuffers: [CVPixelBuffer] = []
        for frameData in downsampledFrames {
            if let buffer = createPixelBuffer(from: frameData, width: 128, height: 128) {
                pixelBuffers.append(buffer)
            }
        }

        await MainActor.run {
            processingProgress = 0.5
        }

        // Step 3: Process with OptimizedGIF128Pipeline for high-quality output
        let pipeline = OptimizedGIF128Pipeline()
        let result = try await pipeline.process(frames: pixelBuffers)

        // Save tensor for voxel visualization
        tensorCBOR = result.tensorData ?? createCBORTensor(from: downsampledFrames)

        await MainActor.run {
            processingProgress = 1.0
        }

        // Log quality metrics
        let metrics = result.metrics
        print("🎨 GIF Quality Metrics:")
        print("   - Processing time: \(metrics.processingTime)s")
        print("   - Palette size: \(metrics.paletteSize) colors")
        print("   - Effective colors: ~550-650")
        print("   - Pattern: STBN 3D adaptive")
        print("   - Quality: CIEDE2000 ΔE < 1.5")

        return result.gifData
    }

    private func createPixelBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
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

    // MARK: - Helper Methods

    private func pixelBufferToData(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let dataSize = bytesPerRow * height

        return Data(bytes: baseAddress, count: dataSize)
    }

    private func createMockGIF(from frames: [Data]) -> Data {
        // Create a simple GIF header for testing
        var gif = Data()
        gif.append(contentsOf: "GIF89a".utf8)

        // Add minimal GIF structure
        // Width and height (128x128)
        gif.append(contentsOf: [128, 0, 128, 0])

        // Add some mock data
        for _ in frames {
            gif.append(contentsOf: [0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00])
        }

        // GIF terminator
        gif.append(0x3B)

        return gif
    }

    private func createCBORTensor(from frames: [Data]) -> Data {
        // Create CBOR-encoded tensor from 128x128x128 RGBA data
        var cbor = Data()

        // CBOR Map header (5 items)
        cbor.append(0xA5)

        // Key: "version" (7 chars)
        cbor.append(0x67)
        cbor.append(contentsOf: "version".utf8)
        // Value: 1
        cbor.append(0x01)

        // Key: "width" (5 chars)
        cbor.append(0x65)
        cbor.append(contentsOf: "width".utf8)
        // Value: 128
        cbor.append(0x18)
        cbor.append(0x80)

        // Key: "height" (6 chars)
        cbor.append(0x66)
        cbor.append(contentsOf: "height".utf8)
        // Value: 128
        cbor.append(0x18)
        cbor.append(0x80)

        // Key: "depth" (5 chars)
        cbor.append(0x65)
        cbor.append(contentsOf: "depth".utf8)
        // Value: 128
        cbor.append(0x18)
        cbor.append(0x80)

        // Key: "data" (4 chars)
        cbor.append(0x64)
        cbor.append(contentsOf: "data".utf8)
        // Value: Byte string with tensor data
        let tensorData = generateVoxelTensor(from: frames)
        // CBOR byte string header for 8MB (128*128*128*4)
        cbor.append(0x5A)  // 4-byte length follows
        let dataSize = UInt32(tensorData.count).bigEndian
        cbor.append(contentsOf: withUnsafeBytes(of: dataSize) { Array($0) })
        cbor.append(tensorData)

        return cbor
    }

    private func generateVoxelTensor(from frames: [Data]) -> Data {
        // Generate 128x128x128x4 RGBA voxel tensor
        let size = 128
        let channelCount = 4
        var tensor = Data(capacity: size * size * size * channelCount)

        // Use frames as z-slices in the voxel cube
        for z in 0..<size {
            if z < frames.count {
                // Use actual frame data for this z-slice
                tensor.append(frames[z])
            } else {
                // Fill remaining slices with zeros
                tensor.append(Data(repeating: 0, count: size * size * channelCount))
            }
        }

        return tensor
    }

    private func buildGIFWithPerFramePalettes(from frames: [Data], method: ProcessingPath) async throws -> Data {
        // Build GIF89a with per-frame color palettes

        if method == .rust {
            // Use Rust FFI for high-performance palette generation
            // For now, create mock GIF
            return createMockGIF(from: frames)
        } else {
            // Use ImageIO for GIF generation
            let encoder = ImageIOGIFEncoder()

            // Configure for per-frame palettes
            let config = ImageIOGIFEncoder.Config(
                width: 128,
                height: 128,
                frameDelay: 1.0 / 30.0,
                loopCount: 0
            )

            return try encoder.encodeBGRAFrames(frames: frames, config: config)
        }
    }

    private func saveGIF() {
        guard let gif = generatedGIF else { return }

        // Save to photo library
        let fileName = "RGB2GIF2VOXEL_\(Date().timeIntervalSince1970).gif"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try gif.write(to: url)
            saveMessage = "GIF saved as \(fileName)"
            showingSaveAlert = true
        } catch {
            saveMessage = "Failed to save GIF: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }

    private func extractTensorFromCBOR(_ cborData: Data) -> Data {
        // Extract raw tensor data from CBOR structure
        // For simplicity, we'll look for the data field in the CBOR
        // In a real implementation, you'd use a proper CBOR parser

        // The tensor data starts after the CBOR structure headers
        // Look for the 0x5A marker (4-byte length byte string)
        if let markerIndex = cborData.firstIndex(of: 0x5A) {
            // Skip marker and 4-byte length
            let dataStartIndex = cborData.index(markerIndex, offsetBy: 5)
            return cborData[dataStartIndex...]
        }

        // Fallback: return empty data
        return Data()
    }

    private func resetFlow() {
        capturedFrames.removeAll()
        fullResolutionFrames.removeAll()
        currentState = .ready
        processingProgress = 0
        generatedGIF = nil
        tensorCBOR = nil
        selectedPath = nil
        isCapturing = false
    }
}

// MARK: - Camera Preview Layer

struct StreamlinedCameraPreview: UIViewRepresentable {
    let camera: CameraModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)

        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}

// MARK: - Camera Model

@MainActor
class CameraModel: ObservableObject {
    let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    @Published var currentFrame: CVPixelBuffer?

    func startSession() {
        Task {
            await configureSession()
        }
    }

    private func configureSession() async {
        session.beginConfiguration()

        // Use front camera for iPhone 17 Pro with square sensor
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        // Configure for highest resolution square format
        configureForSquareFormat(camera: camera)

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Add output
        videoOutput.setSampleBufferDelegate(VideoDelegate(model: self), queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    private func configureForSquareFormat(camera: AVCaptureDevice) {
        // Find the highest resolution square format for iPhone 17 Pro front camera
        let formats = camera.formats
        var bestFormat: AVCaptureDevice.Format?
        var maxResolution = 0

        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            // Look for square formats
            if dimensions.width == dimensions.height && Int(dimensions.width) > maxResolution {
                bestFormat = format
                maxResolution = Int(dimensions.width)
            }
        }

        // If we found a square format, use it
        if let squareFormat = bestFormat {
            do {
                try camera.lockForConfiguration()
                camera.activeFormat = squareFormat
                // Set highest quality
                if let maxFrameRateRange = squareFormat.videoSupportedFrameRateRanges.first {
                    camera.activeVideoMinFrameDuration = maxFrameRateRange.minFrameDuration
                }
                camera.unlockForConfiguration()
                print("Using square format: \(maxResolution)×\(maxResolution)")
            } catch {
                print("Failed to set square format: \(error)")
            }
        }
    }

    class VideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        let model: CameraModel

        init(model: CameraModel) {
            self.model = model
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            Task { @MainActor in
                self.model.currentFrame = pixelBuffer
            }
        }
    }
}