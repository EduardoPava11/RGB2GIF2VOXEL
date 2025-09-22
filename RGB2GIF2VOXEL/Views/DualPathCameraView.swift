//
//  DualPathCameraView.swift
//  RGB2GIF2VOXEL
//
//  Camera interface with dual processing path selection
//

import SwiftUI
import AVFoundation
import Combine

struct DualPathCameraView: View {
    @StateObject private var viewModel = DualPathCameraViewModel()
    @State private var showPathSelector = false
    @State private var selectedProcessingPath: ProcessingPath = .swift
    
    var body: some View {
        ZStack {
            // Camera preview
            if let session = viewModel.cameraSession {
                DualPathCameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            Image(systemName: "camera.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("Camera Unavailable")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    )
            }
            
            // UI Overlay
            VStack {
                // Top controls
                topControls
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            .padding()
        }
        .sheet(isPresented: $showPathSelector) {
            ProcessingPathSelectorSheet(selectedPath: $selectedProcessingPath)
        }
        .task {
            await viewModel.setupCamera()
        }
        .onReceive(viewModel.$processingComplete) { complete in
            if complete {
                // Processing finished, could show results or reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    viewModel.resetCapture()
                }
            }
        }
    }
    
    @ViewBuilder
    private var topControls: some View {
        HStack {
            // Processing path button
            Button(action: { showPathSelector = true }) {
                HStack(spacing: 8) {
                    Text(selectedProcessingPath.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            
            Spacer()
            
            // Status indicator
            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.currentStage)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
        }
    }
    
    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Capture progress
            if viewModel.isCapturing || viewModel.capturedFrames > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Float(viewModel.capturedFrames) / 256.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 200)
                    
                    Text("\(viewModel.capturedFrames)/256 frames")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Main capture button
            Button(action: handleCaptureAction) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(captureButtonColor)
                        .frame(width: 70, height: 70)
                    
                    if viewModel.isCapturing {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    } else if viewModel.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    }
                }
            }
            .disabled(viewModel.isProcessing)
        }
    }
    
    private var captureButtonColor: Color {
        if viewModel.isProcessing {
            return .orange
        } else if viewModel.isCapturing {
            return .red
        } else {
            return .white
        }
    }
    
    private func handleCaptureAction() {
        if viewModel.isCapturing {
            Task {
                await viewModel.stopCaptureAndProcess(using: selectedProcessingPath)
            }
        } else {
            viewModel.startCapture()
        }
    }
}

// MARK: - Camera Preview

struct DualPathCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewUIView {
        VideoPreviewUIView(session: session)
    }
    
    func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        // Update if needed
    }
}

class VideoPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        videoPreviewLayer.session = session
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Processing Path Selector Sheet

struct ProcessingPathSelectorSheet: View {
    @Binding var selectedPath: ProcessingPath
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ProcessingPathSelectorView(selectedPath: $selectedPath)
                .navigationTitle("Processing Options")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - View Model

@MainActor
class DualPathCameraViewModel: ObservableObject {
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var capturedFrames = 0
    @Published var currentStage = ""
    @Published var processingComplete = false
    @Published var lastError: String?
    
    private var cameraService: CameraService?
    private var frameBuffer: [Data] = []
    
    var cameraSession: AVCaptureSession? {
        cameraService?.session
    }
    
    func setupCamera() async {
        do {
            cameraService = CameraService()
            
            // Check and request permission
            let permission = cameraService?.checkPermission()
            if permission != .authorized {
                if let granted = await cameraService?.requestPermission(), !granted {
                    lastError = "Camera permission denied"
                    return
                }
            }
            
            // Setup session
            try await cameraService?.setupSession()
            
            // Configure frame processing
            cameraService?.frameProcessor = { [weak self] pixelBuffer in
                await self?.processIncomingFrame(pixelBuffer)
            }
            
            // Start session
            await cameraService?.startSession()
            
        } catch {
            lastError = "Camera setup failed: \(error.localizedDescription)"
        }
    }
    
    func startCapture() {
        guard let cameraService = cameraService else { return }
        
        isCapturing = true
        capturedFrames = 0
        frameBuffer.removeAll()
        frameBuffer.reserveCapacity(256)
        
        cameraService.startCapture()
    }
    
    func stopCaptureAndProcess(using path: ProcessingPath) async {
        guard let cameraService = cameraService else { return }
        
        isCapturing = false
        cameraService.stopCapture()
        
        guard !frameBuffer.isEmpty else {
            lastError = "No frames captured"
            return
        }
        
        isProcessing = true
        currentStage = "Processing \(frameBuffer.count) frames..."
        
        do {
            // Simulate processing with selected path
            let result = try await simulateProcessing(frames: frameBuffer, path: path)
            
            currentStage = "Processing complete!"
            processingComplete = true
            
            // Save result (would integrate with actual storage service)
            print("✅ Processing completed using \(path.displayName)")
            print("📊 Result: \(result.gifData.count) bytes GIF data")
            
        } catch {
            lastError = "Processing failed: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
    
    func resetCapture() {
        isCapturing = false
        isProcessing = false
        capturedFrames = 0
        processingComplete = false
        frameBuffer.removeAll()
        currentStage = ""
    }
    
    private func processIncomingFrame(_ pixelBuffer: CVPixelBuffer) async {
        guard isCapturing, frameBuffer.count < 256 else { return }
        
        // Extract frame data
        if let frameData = extractFrameData(from: pixelBuffer) {
            frameBuffer.append(frameData)
            capturedFrames = frameBuffer.count
            
            // Auto-stop at 256 frames
            if capturedFrames >= 256 {
                isCapturing = false
                cameraService?.stopCapture()
            }
        }
    }
    
    private func extractFrameData(from pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
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
    
    private func simulateProcessing(frames: [Data], path: ProcessingPath) async throws -> ProcessingResult {
        // Simulate different processing times for different paths
        let processingTime: Double = path == .rustFFI ? 1.5 : 2.5
        
        currentStage = "Initializing \(path.displayName)..."
        try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))
        
        currentStage = "Downsampling frames..."
        try await Task.sleep(nanoseconds: UInt64(processingTime * 0.3 * 1_000_000_000))
        
        currentStage = "Color quantization..."
        try await Task.sleep(nanoseconds: UInt64(processingTime * 0.4 * 1_000_000_000))
        
        currentStage = "GIF encoding..."
        try await Task.sleep(nanoseconds: UInt64(processingTime * 0.3 * 1_000_000_000))
        
        // Create dummy result
        let gifData = Data("GIF89a".utf8) + Data(repeating: 0, count: 1024)
        
        return ProcessingResult(
            gifData: gifData,
            tensorData: nil,
            processingPath: path,
            metrics: ProcessingMetrics()
        )
    }
}

// MARK: - Supporting Types (simplified for demo)

// ProcessingResult is defined in ProcessingTypes.swift