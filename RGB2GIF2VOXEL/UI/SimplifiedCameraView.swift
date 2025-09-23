//
//  SimplifiedCameraView.swift
//  RGB2GIF2VOXEL
//
//  Simplified, stable camera view with clear user flow
//

import SwiftUI
import AVFoundation
import Photos
import os
import Combine
import ImageIO
import UniformTypeIdentifiers

struct SimplifiedCameraView: View {
    @StateObject private var viewModel = StableCameraViewModel()
    @State private var showingSaveSuccess = false
    @State private var savedAssetID: String?

    // MARK: - Helpers

    private func saveGIF(_ data: Data) async {
        viewModel.state = .saving
        viewModel.processingMessage = "Saving to Photos..."

        do {
            savedAssetID = try await PhotosGIFSaver.saveGIF(data).localIdentifier
            viewModel.state = .complete
            showingSaveSuccess = true
        } catch {
            viewModel.errorMessage = "Failed to save GIF: \(error.localizedDescription)"
            viewModel.showingError = true
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Square Camera Preview
            SquareCameraPreview(session: viewModel.session)
                .overlay(captureOverlay)

            VStack {
                // Top status bar
                topStatusBar
                    .padding(.top, 50)

                Spacer()

                // Bottom controls
                bottomControls
                    .padding(.bottom, 50)
            }

            // Processing overlay
            if viewModel.isProcessing {
                processingOverlay
            }

            // Success overlay
            if showingSaveSuccess {
                successOverlay
            }
        }
        .onAppear {
            viewModel.setupCamera()
        }
        .onDisappear {
            // Stop capture if active and cleanup
            if viewModel.state == .capturing {
                viewModel.stopCapture()
            }
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.resetToReady()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private var topStatusBar: some View {
        HStack {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(viewModel.statusText)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Frame counter and memory pressure
            HStack(spacing: 12) {
                if viewModel.frameCount > 0 {
                    Text("\(viewModel.frameCount)/128")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                // Memory pressure indicator
                if viewModel.memoryPressure > 0.5 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(viewModel.memoryPressure > 0.75 ? .red : .orange)
                        Text("\(Int(viewModel.memoryPressure * 100))%")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.2), in: Capsule())
                }
            }
        }
        .padding(.horizontal)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .ready: return .green
        case .preparing: return .yellow
        case .capturing: return .red
        case .processing: return .orange
        case .saving: return .blue
        case .complete: return .green
        case .error: return .red
        }
    }

    @ViewBuilder
    private var captureOverlay: some View {
        if viewModel.state == .capturing {
            Rectangle()
                .strokeBorder(Color.red, lineWidth: 4)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: viewModel.state)
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 30) {
            // Progress bar during capture
            if viewModel.progress > 0 && viewModel.progress < 1 {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .scaleEffect(y: 2)

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 40)
            }

            // Main capture button or action buttons
            if viewModel.state == .ready && viewModel.hasFrames {
                // Show processing buttons after capture
                processingPathButtons
            } else {
                // Show capture button
                captureButton
            }
        }
    }

    private var captureButton: some View {
        Button {
            if viewModel.state == .capturing {
                viewModel.stopCapture()
            } else {
                Task {
                    await viewModel.startCapture()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(viewModel.state == .capturing ? Color.red : Color.white)
                    .frame(width: 70, height: 70)

                if viewModel.state != .capturing {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.black)
                } else {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 25))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(viewModel.state.isActive && viewModel.state != .capturing)
        .scaleEffect(viewModel.state == .capturing ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
    }

    @ViewBuilder
    private var processingPathButtons: some View {
        HStack(spacing: 20) {
            processingButton(
                title: "Fast",
                subtitle: "Swift/ImageIO",
                color: .blue,
                action: {
                    Task {
                        do {
                            let gifData = try await viewModel.processFrames(using: .swift)
                            await saveGIF(gifData)
                        } catch {
                            // Error handled in view model
                        }
                    }
                }
            )

            processingButton(
                title: "Quality",
                subtitle: "Rust/NeuQuant",
                color: .orange,
                action: {
                    Task {
                        do {
                            let gifData = try await viewModel.processFrames(using: .rust)
                            await saveGIF(gifData)
                        } catch {
                            // Error handled in view model
                        }
                    }
                }
            )
        }
        .padding(.horizontal, 40)
    }

    private func processingButton(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Activity indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                // Status text
                Text(viewModel.processingMessage)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Progress
                if viewModel.progress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.progress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(width: 200)

                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)

                Text("GIF Saved!")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Your GIF has been saved to Photos")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

                Button {
                    showingSaveSuccess = false
                    viewModel.resetToReady()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Square Camera Preview Component

struct SquareCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                // Update to square aspect ratio
                let size = min(uiView.bounds.width, uiView.bounds.height)
                let x = (uiView.bounds.width - size) / 2
                let y = (uiView.bounds.height - size) / 2
                previewLayer.frame = CGRect(x: x, y: y, width: size, height: size)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Preview

struct SimplifiedCameraView_Previews: PreviewProvider {
    static var previews: some View {
        SimplifiedCameraView()
    }
}