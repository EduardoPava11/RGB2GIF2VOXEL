//
//  MinimalCaptureView.swift
//  RGB2GIF2VOXEL
//
//  Minimal SwiftUI view for capturing exactly 128 frames at 128x128
//

import SwiftUI
import AVFoundation

/// Minimal view that captures exactly 128 frames to create N=128 GIF
public struct MinimalCaptureView: View {

    @StateObject private var pipeline = CaptureToGIFPipeline()
    @State private var isCameraReady = false
    @State private var showingResult = false

    public init() {}

    public var body: some View {
        ZStack {
            // Camera preview layer
            CameraPreviewLayer(session: pipeline.getCameraSession())
                .ignoresSafeArea()

            VStack {
                // Status display
                VStack(spacing: 8) {
                    Text("N=128 GIF Capture")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)

                    if pipeline.isCapturing || pipeline.isProcessing {
                        ProgressView(value: pipeline.progress) {
                            HStack {
                                if pipeline.isCapturing {
                                    Text("Capturing: \(pipeline.capturedFrames)/128")
                                } else {
                                    Text(pipeline.currentStage)
                                }
                            }
                            .foregroundColor(.white)
                        }
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                        .frame(width: 250)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 100)

                Spacer()

                // Capture button
                if !pipeline.isCapturing && !pipeline.isProcessing {
                    Button(action: startCapture) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 80, height: 80)

                            Circle()
                                .strokeBorder(Color.red, lineWidth: 4)
                                .frame(width: 70, height: 70)

                            Text("128")
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.bottom, 50)
                    .disabled(!isCameraReady)
                    .opacity(isCameraReady ? 1 : 0.5)
                }

                // Result display
                if showingResult, let gifURL = pipeline.lastGIFURL {
                    VStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)

                        Text("GIF Saved!")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(gifURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(15)
                    .padding(.bottom, 50)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .task {
            await setupCamera()
        }
        .onChange(of: pipeline.lastGIFURL) { newValue in
            if newValue != nil {
                withAnimation {
                    showingResult = true
                }

                // Hide result after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showingResult = false
                    }
                }
            }
        }
    }

    private func setupCamera() async {
        await pipeline.setupCamera()
        isCameraReady = true
    }

    private func startCapture() {
        Task {
            await pipeline.startCapture()
        }
    }
}

// MARK: - Camera Preview Layer

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Store the preview layer for layout updates
        view.layer.setValue(previewLayer, forKey: "previewLayer")

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame
        if let previewLayer = uiView.layer.value(forKey: "previewLayer") as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

// MARK: - Preview Provider

struct MinimalCaptureView_Previews: PreviewProvider {
    static var previews: some View {
        MinimalCaptureView()
    }
}