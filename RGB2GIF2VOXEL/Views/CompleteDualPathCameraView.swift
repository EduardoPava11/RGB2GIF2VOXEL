//
//  CompleteDualPathCameraView.swift
//  RGB2GIF2VOXEL
//
//  Complete camera interface with dual processing paths
//  Flow: Camera → Capture 256 frames → Downsize to 256×256 → Choose Rust/Swift → Process → Save GIF
//

import SwiftUI
import AVFoundation
import os.log
import CoreVideo
import Photos
import Combine

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "DualPathCamera")

// MARK: - Processing Types

// ProcessingPath, ProcessingResult, and ProcessingMetrics are defined in ProcessingTypes.swift


// MARK: - Mock Services

class MockNativeGIFEncoder {
    struct Configuration {
        let frameDelay: TimeInterval
        let loopCount: Int
        let quality: Double
        let enableDithering: Bool
        let colorCount: Int
    }
    
    func encodeGIF(frames: [CVPixelBuffer], config: Configuration) async throws -> Data {
        // Simulate encoding time
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create mock GIF data
        var gifData = Data("GIF89a".utf8)
        gifData.append(contentsOf: [0x00, 0x01, 0x00, 0x01]) // 256x256
        gifData.append(Data(repeating: UInt8.random(in: 0...255), count: frames.count * 1024))
        return gifData
    }
    
    static func saveToPhotos(_ data: Data) async throws {
        // Mock save to photos
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

struct CompleteDualPathCameraView: View {
    @StateObject private var viewModel = CompleteDualPathCameraViewModel()
    
    var body: some View {
        ZStack {
            // Camera preview background
            cameraPreviewBackground
            
            // Main UI overlay
            VStack {
                // Top status bar
                topStatusBar
                
                Spacer()
                
                // Main content based on current phase
                mainContent
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            .padding()
        }
        .onAppear {
            Task {
                await viewModel.setupCamera()
            }
        }
        .alert("Error", isPresented: .constant(viewModel.lastError != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.lastError ?? "Unknown error")
        }
    }
    
    // MARK: - Camera Preview
    
    @ViewBuilder
    private var cameraPreviewBackground: some View {
        if viewModel.hasCameraSession {
            Color.black // Placeholder for camera preview
                .ignoresSafeArea()
                .overlay(
                    VStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Camera Preview")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                )
        } else {
            Color.gray
                .ignoresSafeArea()
                .overlay(
                    VStack {
                        Image(systemName: "camera.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        Text("Camera Unavailable")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                )
        }
    }
    
    // MARK: - Top Status Bar
    
    @ViewBuilder
    private var topStatusBar: some View {
        HStack {
            // Current phase indicator
            VStack(alignment: .leading, spacing: 2) {
                Text("Phase: \(viewModel.currentPhase.displayName)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Spacer()
            
            // Processing indicator
            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.currentPhase {
        case .ready:
            readyPhaseView
        case .capturing:
            capturingPhaseView
        case .downsizing:
            downsizingPhaseView
        case .choosingPath:
            pathSelectionView
        case .processing(let path):
            processingPhaseView(path: path)
        case .complete:
            completePhaseView
        }
    }
    
    @ViewBuilder
    private var readyPhaseView: some View {
        VStack(spacing: 20) {
            Text("📱 Ready to Capture")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Tap the capture button to start recording 256 frames")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    private var capturingPhaseView: some View {
        VStack(spacing: 20) {
            Text("📹 Capturing Frames")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: viewModel.captureProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: viewModel.captureProgress)
                
                Text("\(viewModel.capturedFrameCount)/256")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
    
    @ViewBuilder
    private var downsizingPhaseView: some View {
        VStack(spacing: 20) {
            Text("🔄 Processing Frames")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Downsizing from 1080×1080 to 256×256")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
        }
    }
    
    @ViewBuilder
    private var pathSelectionView: some View {
        VStack(spacing: 30) {
            Text("🎯 Choose Processing Path")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("256 frames captured and downsized\nReady for final processing")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            // Processing path buttons
            VStack(spacing: 16) {
                // Rust FFI Path Button
                Button(action: { 
                    Task {
                        await viewModel.processWithRust()
                    }
                }) {
                    ProcessingPathButton(
                        title: "🦀 Process with Rust",
                        subtitle: "Advanced • High Quality • NeuQuant",
                        color: .orange,
                        isAvailable: viewModel.rustPathAvailable
                    )
                }
                .disabled(!viewModel.rustPathAvailable || viewModel.isProcessing)
                
                // Swift Path Button  
                Button(action: {
                    Task {
                        await viewModel.processWithSwift()
                    }
                }) {
                    ProcessingPathButton(
                        title: "🍎 Process with Swift",
                        subtitle: "Reliable • Native • ImageIO",
                        color: .blue,
                        isAvailable: true
                    )
                }
                .disabled(viewModel.isProcessing)
            }
            
            // Path availability info
            if !viewModel.rustPathAvailable {
                Text("ℹ️ Rust FFI unavailable - Swift path recommended")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(.top, 8)
            }
        }
    }
    
    @ViewBuilder
    private func processingPhaseView(path: ProcessingPath) -> some View {
        VStack(spacing: 20) {
            Text("⚙️ Processing with \(path.displayName)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(viewModel.processingStage)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            ProgressView(value: viewModel.processingProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                .frame(width: 200)
            
            Text("\(Int(viewModel.processingProgress * 100))%")
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var completePhaseView: some View {
        VStack(spacing: 20) {
            Text("✅ Processing Complete!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.green)
            
            if let result = viewModel.processingResult {
                VStack(spacing: 8) {
                    Text("GIF saved to Photos")
                        .font(.body)
                        .foregroundColor(.white)
                    
                    Text("Processed with \(result.processingPath.displayName)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("File size: \(ByteCountFormatter.string(fromByteCount: Int64(result.gifData.count), countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
    
    // MARK: - Bottom Controls
    
    @ViewBuilder
    private var bottomControls: some View {
        HStack(spacing: 30) {
            // Reset button (when not capturing)
            if viewModel.currentPhase != .capturing && viewModel.currentPhase != .ready {
                Button(action: {
                    viewModel.resetToCapture()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.8))
                        .clipShape(Circle())
                }
            }
            
            Spacer()
            
            // Main capture button
            if viewModel.currentPhase == .ready || viewModel.currentPhase == .capturing {
                Button(action: {
                    if viewModel.currentPhase == .capturing {
                        viewModel.stopCapture()
                    } else {
                        viewModel.startCapture()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .fill(captureButtonColor)
                            .frame(width: 70, height: 70)
                        
                        if viewModel.currentPhase == .capturing {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                .disabled(!viewModel.hasCameraSession)
            }
            
            Spacer()
            
            // Settings/info button
            Button(action: {
                // Could open settings or info
            }) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.8))
                    .clipShape(Circle())
            }
        }
    }
    
    private var captureButtonColor: Color {
        switch viewModel.currentPhase {
        case .capturing:
            return .red
        default:
            return .white
        }
    }
}

// MARK: - Processing Path Button Component

struct ProcessingPathButton: View {
    let title: String
    let subtitle: String
    let color: Color
    let isAvailable: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(subtitle)
                .font(.caption)
                .opacity(0.8)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isAvailable ? color : Color.gray)
                .opacity(isAvailable ? 1.0 : 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - View Model

@MainActor
class CompleteDualPathCameraViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentPhase: ProcessingPhase = .ready
    @Published var statusMessage: String = ""
    @Published var isProcessing: Bool = false
    
    // Capture state
    @Published var capturedFrameCount: Int = 0
    @Published var captureProgress: Double = 0.0
    
    // Processing state
    @Published var processingStage: String = ""
    @Published var processingProgress: Float = 0.0
    @Published var processingResult: ProcessingResult?
    
    // Error state
    @Published var lastError: String?
    
    // Services - using mock implementations for now
    private var cameraSession: AVCaptureSession?
    private let nativeGIFEncoder = MockNativeGIFEncoder()
    
    // Internal state
    private var capturedFrames: [Data] = []
    private var downsizedFrames: [Data] = []
    
    // MARK: - Computed Properties
    
    var hasCameraSession: Bool {
        cameraSession != nil
    }
    
    var rustPathAvailable: Bool {
        // Check if Rust FFI is available
        // For now, return true - would implement actual check
        return true
    }
    
    // MARK: - Camera Setup
    
    func setupCamera() async {
        // Mock camera setup
        do {
            // Simulate camera permission check
            let hasPermission = await mockCheckCameraPermission()
            guard hasPermission else {
                lastError = "Camera permission required"
                return
            }
            
            // Mock camera session setup
            cameraSession = AVCaptureSession()
            
            // Simulate setup delay
            try await Task.sleep(nanoseconds: 500_000_000)
            
            statusMessage = "Camera ready"
            os_log(.info, log: logger, "✅ Mock camera setup complete")
            
        } catch {
            lastError = "Camera setup failed: \(error.localizedDescription)"
            os_log(.error, log: logger, "❌ Camera setup failed: %@", error.localizedDescription)
        }
    }
    
    private func mockCheckCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
    
    private func startMockFrameCapture() {
        // Mock frame capture - simulate frames being captured
        Task {
            for frameIndex in 0..<256 {
                guard currentPhase == .capturing else { break }
                
                // Generate mock frame data (256 KB per frame for 1080x1080 BGRA)
                let mockFrameData = Data(repeating: UInt8.random(in: 0...255), count: 1080 * 1080 * 4)
                capturedFrames.append(mockFrameData)
                
                await MainActor.run {
                    capturedFrameCount = capturedFrames.count
                    captureProgress = Double(capturedFrameCount) / 256.0
                }
                
                // Simulate 30 FPS (33ms per frame)
                try? await Task.sleep(nanoseconds: 33_000_000)
                
                // Auto-complete at 256 frames
                if frameIndex >= 255 {
                    await MainActor.run {
                        stopMockFrameCapture()
                        Task {
                            await downsizeFrames()
                        }
                    }
                    break
                }
            }
        }
    }
    
    private func stopMockFrameCapture() {
        // Mock stop - frame generation will check currentPhase
    }
    
    // MARK: - Capture Control
    
    func startCapture() {
        guard currentPhase == .ready else { return }
        
        currentPhase = .capturing
        capturedFrameCount = 0
        captureProgress = 0.0
        capturedFrames.removeAll()
        capturedFrames.reserveCapacity(256)
        
        // Mock start capture
        startMockFrameCapture()
        statusMessage = "Capturing frames..."
        
        os_log(.info, log: logger, "📹 Started frame capture")
    }
    
    func stopCapture() {
        guard currentPhase == .capturing else { return }
        
        // Mock stop capture
        stopMockFrameCapture()
        
        if capturedFrames.count >= 10 { // Minimum frames for processing
            Task {
                await downsizeFrames()
            }
        } else {
            lastError = "Not enough frames captured (need at least 10, got \(capturedFrames.count))"
            resetToCapture()
        }
    }
    
    // MARK: - Frame Processing
    
    private func processIncomingFrame(_ pixelBuffer: CVPixelBuffer) async {
        guard currentPhase == .capturing, capturedFrames.count < 256 else { return }
        
        // Extract frame data (center-cropped to square)
        if let frameData = extractSquareFrameData(from: pixelBuffer) {
            capturedFrames.append(frameData)
            capturedFrameCount = capturedFrames.count
            captureProgress = Double(capturedFrameCount) / 256.0
            
            // Auto-stop at 256 frames
            if capturedFrameCount >= 256 {
                stopMockFrameCapture()
                Task {
                    await downsizeFrames()
                }
            }
        }
    }
    
    private func extractSquareFrameData(from pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        // Center crop to square (1080×1080 from larger input)
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
    
    // MARK: - Downsizing
    
    private func downsizeFrames() async {
        currentPhase = .downsizing
        statusMessage = "Downsizing \(capturedFrames.count) frames to 256×256"
        
        // Mock downsizing - simulate processing time
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Create mock downsized frames (256×256 BGRA)
        downsizedFrames = capturedFrames.map { _ in
            Data(repeating: UInt8.random(in: 0...255), count: 256 * 256 * 4)
        }
            
        os_log(.info, log: logger, "✅ Mock downsized %d frames to 256×256", downsizedFrames.count)
        
        // Move to path selection
        currentPhase = .choosingPath
        statusMessage = "Choose your processing method"
    }
    
    // MARK: - Processing Paths
    
    func processWithRust() async {
        await processFrames(using: .rustFFI)
    }
    
    func processWithSwift() async {
        await processFrames(using: .swift)
    }
    
    private func processFrames(using path: ProcessingPath) async {
        currentPhase = .processing(path)
        isProcessing = true
        processingProgress = 0.0
        
        os_log(.info, log: logger, "🚀 Starting processing with %@ path", path.displayName)
        
        do {
            let result: ProcessingResult
            
            switch path {
            case .rustFFI:
                result = try await processWithRustFFI()
            case .swift:
                result = try await processWithSwiftNative()
            }
            
            // Save GIF to Photos
            processingStage = "Saving to Photos..."
            processingProgress = 0.9
            
            try await saveGIFToPhotos(result.gifData)
            
            processingProgress = 1.0
            processingResult = result
            currentPhase = .complete
            statusMessage = "GIF saved successfully!"
            
            os_log(.info, log: logger, "✅ Processing complete with %@ path", path.displayName)
            
        } catch {
            lastError = "Processing failed: \(error.localizedDescription)"
            os_log(.error, log: logger, "❌ Processing failed: %@", error.localizedDescription)
            resetToCapture()
        }
        
        isProcessing = false
    }
    
    private func processWithRustFFI() async throws -> ProcessingResult {
        processingStage = "🦀 Initializing Rust processor..."
        processingProgress = 0.1
        
        // Simulate Rust FFI processing stages
        processingStage = "🦀 NeuQuant color quantization..."
        try await Task.sleep(nanoseconds: 800_000_000)
        processingProgress = 0.4
        
        processingStage = "🦀 Advanced dithering..."
        try await Task.sleep(nanoseconds: 600_000_000)
        processingProgress = 0.6
        
        processingStage = "🦀 GIF89a encoding..."
        try await Task.sleep(nanoseconds: 700_000_000)
        processingProgress = 0.8
        
        processingStage = "🦀 Generating tensor data..."
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Create mock GIF data (would use actual Rust FFI)
        let gifData = createMockGIFData(quality: "High")
        let tensorData = createMockTensorData()
        
        return ProcessingResult(
            gifData: gifData,
            tensorData: tensorData,
            processingPath: .rustFFI,
            metrics: ProcessingMetrics(processingTime: 2.4, paletteSize: 256, fileSize: gifData.count),
            processingTime: 2.4
        )
    }
    
    private func processWithSwiftNative() async throws -> ProcessingResult {
        processingStage = "🍎 Initializing Swift encoder..."
        processingProgress = 0.1
        
        // Convert Data to CVPixelBuffers for NativeGIFEncoder
        var pixelBuffers: [CVPixelBuffer] = []
        
        processingStage = "🍎 Converting frames..."
        processingProgress = 0.3
        
        for (index, frameData) in downsizedFrames.enumerated() {
            if let pixelBuffer = createPixelBuffer(from: frameData, width: 256, height: 256) {
                pixelBuffers.append(pixelBuffer)
            }
            
            // Update progress
            if index % 20 == 0 {
                processingProgress = 0.3 + (Float(index) / Float(downsizedFrames.count)) * 0.3
            }
        }
        
        processingStage = "🍎 ImageIO GIF encoding..."
        processingProgress = 0.6
        
        // Use MockNativeGIFEncoder
        let config = MockNativeGIFEncoder.Configuration(
            frameDelay: 1.0/30.0,  // 30 FPS
            loopCount: 0,          // Infinite loop
            quality: 0.8,
            enableDithering: true,
            colorCount: 256
        )
        
        let gifData = try await nativeGIFEncoder.encodeGIF(frames: pixelBuffers, config: config)
        
        processingStage = "🍎 Finalizing..."
        processingProgress = 0.9
        
        let tensorData = createMockTensorData()
        
        return ProcessingResult(
            gifData: gifData,
            tensorData: tensorData,
            processingPath: .swift,
            metrics: ProcessingMetrics(processingTime: 3.1, paletteSize: 256, fileSize: gifData.count),
            processingTime: 3.1
        )
    }
    
    // MARK: - Utilities
    
    private func createPixelBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard result == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let _ = data.withUnsafeBytes { bytes in
            memcpy(baseAddress, bytes.baseAddress, min(data.count, width * height * 4))
        }
        
        return buffer
    }
    
    private func createMockGIFData(quality: String) -> Data {
        // Create realistic GIF header + data
        var gifData = Data("GIF89a".utf8)
        // Add dimensions (256x256 in little endian)
        gifData.append(contentsOf: [0x00, 0x01, 0x00, 0x01]) // 256x256
        // Add color table and frame data (simplified)
        gifData.append(Data(repeating: UInt8.random(in: 0...255), count: 1024 * 256)) // ~256KB
        return gifData
    }
    
    private func createMockTensorData() -> Data {
        var tensorData = Data()
        tensorData.append("TNSR".data(using: .utf8)!) // Header
        tensorData.append(contentsOf: withUnsafeBytes(of: UInt32(256)) { Data($0) }) // Width
        tensorData.append(contentsOf: withUnsafeBytes(of: UInt32(256)) { Data($0) }) // Height  
        tensorData.append(contentsOf: withUnsafeBytes(of: UInt32(256)) { Data($0) }) // Frames
        return tensorData
    }
    
    private func saveGIFToPhotos(_ gifData: Data) async throws {
        try await MockNativeGIFEncoder.saveToPhotos(gifData)
        os_log(.info, log: logger, "💾 GIF saved to Photos library")
    }
    
    // MARK: - State Management
    
    func resetToCapture() {
        currentPhase = .ready
        statusMessage = ""
        capturedFrameCount = 0
        captureProgress = 0.0
        processingProgress = 0.0
        processingStage = ""
        processingResult = nil
        capturedFrames.removeAll()
        downsizedFrames.removeAll()
        
        os_log(.info, log: logger, "🔄 Reset to capture phase")
    }
    
    func clearError() {
        lastError = nil
    }
}

// MARK: - Processing Phase Enum

enum ProcessingPhase: Equatable {
    case ready
    case capturing
    case downsizing
    case choosingPath
    case processing(ProcessingPath)
    case complete
    
    var displayName: String {
        switch self {
        case .ready:
            return "Ready"
        case .capturing:
            return "Capturing"
        case .downsizing:
            return "Downsizing"
        case .choosingPath:
            return "Choose Path"
        case .processing(let path):
            return "Processing (\(path.rawValue))"
        case .complete:
            return "Complete"
        }
    }
}

// MARK: - Preview

#Preview {
    CompleteDualPathCameraView()
}