//
//  CameraScreen.swift
//  RGB2GIF2VOXEL
//
//  Main camera capture screen with clean architecture
//

import SwiftUI
import AVFoundation
import Combine

struct CameraScreen: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var videoOrientation = AVCaptureVideoOrientation.portrait

    var body: some View {
        ZStack {
            // Camera preview background
            CameraScreenPreviewView(session: viewModel.cameraService.session)
                .edgesIgnoringSafeArea(.all)

            // UI overlay
            VStack {
                // Top bar with status
                topBar

                Spacer()

                // Capture progress
                if viewModel.isCapturing {
                    captureProgressView
                }

                // Bottom controls
                bottomControls
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            videoOrientation = UIDevice.current.orientation.videoOrientation
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Processing Complete", isPresented: $viewModel.showSuccess) {
            Button("Save to Photos") {
                Task {
                    await viewModel.saveToPhotos()
                }
            }
            Button("Done") { }
        } message: {
            Text("GIF created successfully!")
        }
    }

    // MARK: - UI Components

    private var topBar: some View {
        HStack {
            // Settings button
            Button(action: { }) {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            // Status indicator
            if viewModel.isCapturing {
                Label("CAPTURING", systemImage: "circle.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
            } else if viewModel.isProcessing {
                Label("PROCESSING", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
            }

            Spacer()

            // Gallery button
            Button(action: { }) {
                Image(systemName: "photo.stack")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    private var captureProgressView: some View {
        VStack(spacing: 20) {
            // Frame counter
            Text("\(viewModel.capturedFrames) / 256")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            // Progress bar
            ProgressView(value: viewModel.captureProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .tint(.blue)
                .scaleEffect(y: 2)
                .padding(.horizontal, 40)

            // Stage indicator
            if !viewModel.currentStage.isEmpty {
                Text(viewModel.currentStage)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(15)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    private var bottomControls: some View {
        VStack(spacing: 30) {
            // Capture button
            Button(action: viewModel.toggleCapture) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 80, height: 80)

                    Circle()
                        .fill(viewModel.isCapturing ? Color.red : Color.white)
                        .frame(width: 70, height: 70)

                    if viewModel.isCapturing {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .disabled(viewModel.isProcessing)
        }
        .padding(.bottom, 50)
    }
}

// MARK: - Camera Preview View

struct CameraScreenPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // Ensure frame is updated
        uiView.videoPreviewLayer.frame = uiView.bounds
    }

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
        }
    }
}

// MARK: - View Model

@MainActor
class CameraViewModel: ObservableObject {
    // Services
    let cameraService = CameraService()
    private let processingService = ProcessingService()
    private let storageService = StorageService()

    // Published state
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var capturedFrames = 0
    @Published var captureProgress: Double = 0
    @Published var currentStage = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showSuccess = false

    // Internal state
    private var frameBuffer: [Data] = []
    private let targetFrameCount = 256
    private let captureSize = 1080
    private let outputSize = 256
    private var lastGIFURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    private func setupBindings() {
        cameraService.$isCapturing
            .assign(to: &$isCapturing)
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task {
            await setupCamera()
        }
    }

    func onDisappear() {
        cameraService.stopSession()
    }

    private func setupCamera() async {
        // Check permission
        let status = cameraService.checkPermission()
        print("📱 [CAMERA] Current permission status: \(status.rawValue)")

        switch status {
        case .authorized:
            print("✅ [CAMERA] Permission already granted")
            await startCamera()
        case .notDetermined:
            print("❓ [CAMERA] Permission not determined, requesting...")
            let granted = await cameraService.requestPermission()
            if granted {
                print("✅ [CAMERA] Permission granted by user")
                await startCamera()
            } else {
                print("❌ [CAMERA] Permission denied by user")
                showError(message: "Camera permission is required")
            }
        case .denied, .restricted:
            print("🚫 [CAMERA] Permission denied or restricted")
            showError(message: "Camera access denied. Please enable in Settings.")
        @unknown default:
            print("⚠️ [CAMERA] Unknown permission status")
            showError(message: "Unknown camera permission status")
        }
    }

    private func startCamera() async {
        print("🎬 [CAMERA] Starting camera session setup...")
        do {
            try await cameraService.setupSession()
            print("✅ [CAMERA] Session setup complete")

            cameraService.startSession()
            print("▶️ [CAMERA] Session started")

            // Set up frame processor
            cameraService.frameProcessor = { [weak self] pixelBuffer in
                await self?.processFrame(pixelBuffer)
            }
            print("📷 [CAMERA] Frame processor configured")
        } catch {
            print("❌ [CAMERA] Failed to start camera: \(error.localizedDescription)")
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Capture Control

    func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    private func startCapture() {
        frameBuffer.removeAll()
        frameBuffer.reserveCapacity(targetFrameCount)
        capturedFrames = 0
        captureProgress = 0
        currentStage = "Capturing frames..."

        cameraService.startCapture()
    }

    private func stopCapture() {
        cameraService.stopCapture()

        if frameBuffer.count > 0 {
            Task {
                await processFramesToGIF()
            }
        }
    }

    // MARK: - Frame Processing

    private func processFrame(_ pixelBuffer: CVPixelBuffer) async {
        guard isCapturing else { return }
        guard frameBuffer.count < targetFrameCount else {
            stopCapture()
            return
        }

        let bgraData = processingService.extractBGRAData(from: pixelBuffer)
        frameBuffer.append(bgraData)

        await MainActor.run {
            capturedFrames = frameBuffer.count
            captureProgress = Double(capturedFrames) / Double(targetFrameCount)
        }
    }

    private func processFramesToGIF() async {
        isProcessing = true
        currentStage = "Processing..."

        do {
            // Process to GIF
            let gifData = try await processingService.processToGIF(
                frames: frameBuffer,
                captureSize: captureSize,
                targetSize: outputSize
            )

            // Save GIF
            currentStage = "Saving..."
            let gifURL = try storageService.saveGIF(gifData)
            lastGIFURL = gifURL

            // Show success
            await MainActor.run {
                isProcessing = false
                showSuccess = true
            }

        } catch {
            await MainActor.run {
                isProcessing = false
                showError(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Export

    func saveToPhotos() async {
        guard let gifURL = lastGIFURL else { return }

        do {
            try await storageService.saveGIFToPhotos(gifURL)
        } catch {
            await MainActor.run {
                showError(message: "Failed to save to Photos: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Error Handling

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

#Preview {
    CameraScreen()
}