//
//  ImprovedCameraView.swift
//  RGB2GIF2VOXEL
//
//  SwiftUI camera view with working preview and proper lifecycle
//

import SwiftUI
import AVFoundation
import Photos
import os

struct ImprovedCameraView: View {
    @StateObject private var pipeline = SingleFFIPipelineImproved()
    @StateObject private var cameraManager = ImprovedCameraManager()
    @State private var showingPathSelection = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Square Camera Preview (1080x1080)
            SquareCameraPreview(session: cameraManager.session)
                .onAppear {
                    Task {
                        await setupCamera()
                    }
                }
                .onDisappear {
                    cameraManager.stopSession()
                }

            // UI Overlay
            VStack {
                // Top bar with status
                HStack {
                    statusBadge
                    Spacer()
                    frameCountBadge
                }
                .padding()

                Spacer()

                // Bottom controls
                VStack(spacing: 20) {
                    progressView

                    captureButton
                }
                .padding(.bottom, 50)
            }

            // Path selection sheet
            if showingPathSelection {
                pathSelectionOverlay
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(pipeline.currentPhase.isEmpty ? "Ready" : pipeline.currentPhase)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch pipeline.state {
        case .idle: return .gray
        case .capturingFrames: return .red
        case .processingSwift, .processingRust, .downsampling, .encodingCBOR: return .orange
        case .complete: return .green
        case .failed: return .red
        default: return .blue
        }
    }

    @ViewBuilder
    private var frameCountBadge: some View {
        if pipeline.capturedFrameCount > 0 {
            Text("\(pipeline.capturedFrameCount)/256")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if pipeline.progress > 0 {
            VStack {
                ProgressView(value: pipeline.progress)
                    .progressViewStyle(.linear)
                    .tint(.white)

                Text("\(Int(pipeline.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 40)
        }
    }

    private var captureButton: some View {
        Button {
            Task {
                await startCapture()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)

                if pipeline.state == .capturingFrames {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 50, height: 50)
                } else {
                    Circle()
                        .strokeBorder(Color.black, lineWidth: 3)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(pipeline.state != .idle)
    }

    private var pathSelectionOverlay: some View {
        VStack(spacing: 30) {
            Text("Select Processing Path")
                .font(.title2)
                .bold()

            VStack(spacing: 20) {
                pathButton(
                    title: "Swift Native",
                    subtitle: "Uses ImageIO",
                    icon: "swift",
                    action: selectSwiftPath
                )

                pathButton(
                    title: "Rust FFI",
                    subtitle: "Uses NeuQuant",
                    icon: "cpu",
                    action: selectRustPath
                )
            }
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(40)
    }

    private func pathButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func setupCamera() async {
        do {
            Log.ui.info("Setting up camera for preview")
            try await cameraManager.setupSession()
            cameraManager.startSession()
            Log.ui.info("✅ Camera preview started")
        } catch {
            Log.ui.error("Failed to setup camera: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func startCapture() async {
        do {
            await pipeline.runPipeline()

            if case .complete = pipeline.state {
                Log.ui.info("✅ Pipeline complete, GIF saved to Photos")
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func selectSwiftPath() {
        showingPathSelection = false
        Task {
            do {
                let gifData = try await pipeline.selectSwiftPath()
                _ = try await PhotosGIFSaver.saveGIF(gifData)
                Log.ui.info("✅ Swift path complete")
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func selectRustPath() {
        showingPathSelection = false
        Task {
            do {
                let gifData = try await pipeline.selectRustPath()
                _ = try await PhotosGIFSaver.saveGIF(gifData)
                Log.ui.info("✅ Rust path complete")
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Preview

struct ImprovedCameraView_Previews: PreviewProvider {
    static var previews: some View {
        ImprovedCameraView()
    }
}