//
//  IntegratedCaptureVoxelView.swift
//  RGB2GIF2VOXEL
//
//  Complete N=128 capture → GIF89a → Voxel visualization pipeline
//

import SwiftUI
import AVFoundation

/// Integrated view that captures 128 frames, creates GIF89a, and shows voxel visualization
public struct IntegratedCaptureVoxelView: View {

    @StateObject private var pipeline = CaptureToGIFPipeline()
    @State private var isCameraReady = false
    @State private var showingVoxels = false

    public init() {}

    public var body: some View {
        ZStack {
            if !showingVoxels {
                // Camera capture view
                CameraPreviewLayer(session: pipeline.getCameraSession())
                    .ignoresSafeArea()

                VStack {
                    // Header
                    VStack(spacing: 8) {
                        Text("N=128 GIF89a → Voxel Pipeline")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)

                        if pipeline.isCapturing || pipeline.isProcessing {
                            ProgressView(value: pipeline.progress) {
                                VStack(spacing: 4) {
                                    if pipeline.isCapturing {
                                        Text("Capturing: \(pipeline.capturedFrames)/128")
                                            .font(.headline)
                                    } else {
                                        Text(pipeline.currentStage)
                                            .font(.headline)
                                    }

                                    // Show detailed progress
                                    Group {
                                        if pipeline.currentStage.contains("Downsampling") {
                                            Text("Resizing to 128×128")
                                                .font(.caption)
                                        } else if pipeline.currentStage.contains("tensor") {
                                            Text("Creating 128³ voxel data")
                                                .font(.caption)
                                        } else if pipeline.currentStage.contains("GIF89a") {
                                            Text("Encoding with STBN dithering")
                                                .font(.caption)
                                        }
                                    }
                                    .foregroundColor(.white.opacity(0.8))
                                }
                                .foregroundColor(.white)
                            }
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 300)
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
                                    .fill(
                                        LinearGradient(
                                            colors: [.red, .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 90, height: 90)

                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 3)
                                    .frame(width: 85, height: 85)

                                VStack(spacing: 2) {
                                    Text("128")
                                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    Text("CAPTURE")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .padding(.bottom, 50)
                        .disabled(!isCameraReady)
                        .opacity(isCameraReady ? 1 : 0.5)
                        .scaleEffect(isCameraReady ? 1 : 0.9)
                        .animation(.easeInOut(duration: 0.3), value: isCameraReady)
                    }

                    // Show info during capture
                    if pipeline.isCapturing {
                        VStack(spacing: 4) {
                            Text("Hold steady!")
                                .font(.headline)
                                .foregroundColor(.yellow)

                            Text("Capturing at 128×128")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                    }
                }
            } else {
                // Voxel visualization
                if let tensorData = pipeline.lastTensorData,
                   let gifData = pipeline.lastGIFURL?.dataRepresentation {
                    VoxelVisualizationScreen(
                        gifData: gifData,
                        tensorData: tensorData
                    )
                    .transition(.opacity.combined(with: .scale))

                    // Back button
                    VStack {
                        HStack {
                            Button(action: {
                                withAnimation {
                                    showingVoxels = false
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
        }
        .task {
            await setupCamera()
        }
        .onChange(of: pipeline.lastTensorData) { newValue in
            if newValue != nil && pipeline.lastGIFURL != nil {
                // Automatically show voxels when processing completes
                withAnimation(.easeInOut(duration: 0.5)) {
                    showingVoxels = true
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

// MARK: - URL Extension

extension URL {
    var dataRepresentation: Data? {
        try? Data(contentsOf: self)
    }
}

// MARK: - Preview

struct IntegratedCaptureVoxelView_Previews: PreviewProvider {
    static var previews: some View {
        IntegratedCaptureVoxelView()
    }
}