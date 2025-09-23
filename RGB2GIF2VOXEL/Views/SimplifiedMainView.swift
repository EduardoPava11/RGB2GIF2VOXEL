//
//  SimplifiedMainView.swift
//  RGB2GIF2VOXEL
//
//  Streamlined UX with Swift-only path and 3D cube visualization
//

import SwiftUI
import AVFoundation
import Photos
import Combine

public struct SimplifiedMainView: View {
    @StateObject private var cameraModel = SimplifiedCameraModel()
    @State private var showingCube = false
    @State private var capturedGIF: Data?
    @State private var savedToPhotos = false
    @State private var showingSaveAlert = false

    public init() {}

    public var body: some View {
        ZStack {
            // Main content
            if !showingCube {
                // Camera capture view
                cameraView
            } else if let gifData = capturedGIF {
                // 3D Cube visualization with Metal
                Enhanced3DVoxelView(gifData: gifData)
                    .overlay(alignment: .topLeading) {
                        backButton
                    }
                    .overlay(alignment: .bottomTrailing) {
                        saveButton
                    }
            }
        }
        .preferredColorScheme(.dark)
        .alert("GIF Saved!", isPresented: $showingSaveAlert) {
            Button("OK") {
                // Reset for new capture
                showingCube = false
                capturedGIF = nil
                savedToPhotos = false
                cameraModel.reset()
            }
        } message: {
            Text("Your GIF has been saved to Photos")
        }
    }

    private var cameraView: some View {
        ZStack {
            // Camera preview
            SimplifiedCameraPreviewLayer(session: cameraModel.session)
                .ignoresSafeArea()

            // UI Overlay
            VStack {
                // Header
                headerView

                Spacer()

                // Progress or capture button
                if cameraModel.isCapturing {
                    captureProgressView
                } else if cameraModel.isProcessing {
                    processingView
                } else {
                    captureButton
                }

                // Bottom spacer
                Color.clear.frame(height: 100)
            }
        }
        .task {
            await cameraModel.setupCamera()
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("RGB → GIF → VOXEL")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Capture 128 frames for 3D visualization")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.top, 60)
    }

    private var captureProgressView: some View {
        VStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: cameraModel.captureProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: cameraModel.captureProgress)

                VStack {
                    Text("\(cameraModel.framesCaptured)")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                    Text("of 128")
                        .font(.caption)
                        .opacity(0.8)
                }
                .foregroundColor(.white)
            }
            .frame(width: 120, height: 120)

            // Stop button
            Button(action: {
                cameraModel.stopCapture()
            }) {
                Label("Stop", systemImage: "stop.fill")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(25)
            }
        }
        .padding(.bottom, 40)
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))

            Text("Creating your GIF...")
                .font(.headline)
                .foregroundColor(.white)

            Text("Using optimized pipeline")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .padding(.bottom, 40)
    }

    private var captureButton: some View {
        Button(action: {
            Task {
                await startCapture()
            }
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)

                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                // Icon
                Image(systemName: "camera.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
        }
        .padding(.bottom, 40)
        .scaleEffect(cameraModel.buttonScale)
    }

    private var backButton: some View {
        Button(action: {
            withAnimation(.spring()) {
                showingCube = false
            }
        }) {
            HStack {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
        }
        .padding()
    }

    private var saveButton: some View {
        Button(action: {
            Task {
                await saveToPhotos()
            }
        }) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save GIF")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(savedToPhotos ? Color.green : Color.blue)
            )
        }
        .padding()
        .disabled(savedToPhotos)
    }

    private func startCapture() async {
        await cameraModel.startCapture { gifData in
            self.capturedGIF = gifData
            withAnimation(.spring()) {
                self.showingCube = true
            }
        }
    }

    private func saveToPhotos() async {
        guard let gifData = capturedGIF else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: gifData, options: nil)
            }

            savedToPhotos = true
            showingSaveAlert = true
        } catch {
            print("Error saving to photos: \(error)")
        }
    }
}

// MARK: - Camera Model

@MainActor
class SimplifiedCameraModel: ObservableObject {
    @Published var framesCaptured = 0
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var captureProgress: Double = 0
    @Published var buttonScale: CGFloat = 1.0

    let session = AVCaptureSession()
    private var cameraManager: CubeCameraManagerOptimized?
    private var processor: OptimizedGIF128Pipeline?
    private var collectedFrames: [CVPixelBuffer] = []
    private let targetFrameCount = 128

    func setupCamera() async {
        cameraManager = CubeCameraManagerOptimized()
        processor = OptimizedGIF128Pipeline()

        guard let manager = cameraManager else { return }

        await withCheckedContinuation { continuation in
            manager.sessionQueue.async { [weak manager] in
                manager?.setupSession()
                continuation.resume()
            }
        }

        // Copy session configuration
        session.beginConfiguration()
        for input in manager.session.inputs {
            session.addInput(input)
        }
        for output in manager.session.outputs {
            session.addOutput(output)
        }
        session.commitConfiguration()

        session.startRunning()
    }

    func startCapture(completion: @escaping (Data) -> Void) async {
        isCapturing = true
        framesCaptured = 0
        collectedFrames = []

        withAnimation(.spring()) {
            buttonScale = 0.9
        }

        // Set up frame processor
        cameraManager?.frameProcessor = { [weak self] pixelBuffer in
            Task { @MainActor in
                await self?.processFrame(pixelBuffer, completion: completion)
            }
        }

        cameraManager?.startCapture()
    }

    func stopCapture() {
        isCapturing = false
        cameraManager?.stopCapture()
        cameraManager?.frameProcessor = nil

        withAnimation(.spring()) {
            buttonScale = 1.0
        }
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer, completion: @escaping (Data) -> Void) async {
        guard isCapturing else { return }

        // Collect frames
        collectedFrames.append(pixelBuffer)
        framesCaptured += 1
        captureProgress = Double(framesCaptured) / Double(targetFrameCount)

        if framesCaptured >= targetFrameCount {
            stopCapture()
            isProcessing = true

            // Process collected frames into GIF
            do {
                let result = try await processor?.process(frames: collectedFrames)
                if let gifData = result?.gifData {
                    completion(gifData)
                }
            } catch {
                print("Error processing frames: \(error)")
            }

            isProcessing = false
            collectedFrames = []
        }
    }

    func reset() {
        framesCaptured = 0
        isCapturing = false
        isProcessing = false
        captureProgress = 0
        buttonScale = 1.0
        collectedFrames = []
    }
}

// MARK: - Camera Preview

struct SimplifiedCameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        if #available(iOS 17.0, *) {
            previewLayer.connection?.videoRotationAngle = 90
        } else {
            previewLayer.connection?.videoOrientation = .portrait
        }

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


// MARK: - Preview

struct SimplifiedMainView_Previews: PreviewProvider {
    static var previews: some View {
        SimplifiedMainView()
    }
}