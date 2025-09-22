import SwiftUI
import AVFoundation
import CoreMedia

struct CubeCameraView: View {
    @StateObject private var cameraManager = CubeCameraManagerOptimized()
    @State private var selectedN = 256 // Default to HD quality 256×256×256
    @State private var selectedPaletteSize = 256
    @State private var showingGIF = false
    @State private var generatedGIF: Data?
    @State private var showingVoxelViewer = false
    @State private var showingExportMenu = false
    @State private var capturedTensor: CubeTensorData?

    // Updated options with 256×256×256 as primary target
    private let nOptions = [256, 132, 264]
    private let paletteOptions = [256, 128, 64]

    var body: some View {
        ZStack {
            // Live camera preview in a square, no-crop container
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                CameraPreviewLayer(session: cameraManager.session)
                    .frame(width: side, height: side)
                    .clipped()
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .edgesIgnoringSafeArea(.all)

            VStack {
                // Top bar with enhanced format info
                HStack {
                    if let format = cameraManager.currentFormat {
                        HStack(spacing: 6) {
                            Image(systemName: "crop")
                            Text(format.displayText)
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.orange.opacity(0.6)))
                    }

                    Spacer()

                    if cameraManager.isCapturing {
                        VStack(spacing: 4) {
                            Text(cameraManager.clipController.progressText)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundColor(.white)
                            
                            // Enhanced frame count for 256³ cubes
                            if selectedN == 256 {
                                let currentFrame = min(Int(cameraManager.clipController.captureProgress * 256), 256)
                                Text("\(currentFrame)/256 frames")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.8)))
                    }
                }
                .padding()

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    if cameraManager.isCapturing {
                        VStack(spacing: 8) {
                            ProgressView(value: cameraManager.clipController.captureProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: selectedN == 256 ? .yellow : .red))
                                .frame(height: selectedN == 256 ? 6 : 4)
                                .background(Color.white.opacity(0.3))
                                .clipShape(Capsule())
                            
                            // Enhanced progress indicator for 256³
                            if selectedN == 256 {
                                HStack {
                                    Text("HD Capture")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    let progress = cameraManager.clipController.captureProgress
                                    Text(String(format: "%.1f%%", progress * 100))
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }

                    // N selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cube Size (N×N×N)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))

                        HStack {
                            ForEach(nOptions, id: \.self) { (n: Int) in
                                Button {
                                    selectedN = n
                                    cameraManager.updatePyramidLevel(n)
                                } label: {
                                    Text("\(n)")
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(selectedN == n ? .bold : .regular)
                                        .foregroundColor(selectedN == n ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedN == n ? Color.white : Color.white.opacity(0.2))
                                        )
                                }
                            }
                        }
                    }

                    // Palette selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Palette Size")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))

                        Picker("Palette", selection: $selectedPaletteSize) {
                            ForEach(paletteOptions, id: \.self) { p in
                                Text("\(p)").tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedPaletteSize) { newValue in
                            cameraManager.updatePaletteSize(newValue)
                        }
                    }

                    // Info and FPS with HD quality indicators
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Frames needed: \(selectedN)")
                                .font(.caption2)
                            Text("Tensor voxels: \(selectedN * selectedN * selectedN)")
                                .font(.caption2)
                            
                            // Special indicator for 256³ HD mode
                            if selectedN == 256 {
                                HStack(spacing: 4) {
                                    Image(systemName: "crown.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption2)
                                    Text("HD Quality • 8.5s")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .foregroundColor(.white.opacity(0.85))

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f fps", cameraManager.currentFPS))
                                .font(.caption)
                            
                            if selectedN == 256 {
                                Text("Target: 30fps")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .foregroundColor(.white.opacity(0.85))
                    }

                    // Capture controls
                    HStack(spacing: 16) {
                        Button(action: {
                            if cameraManager.isCapturing {
                                cameraManager.stopCapture()
                            } else {
                                cameraManager.startCapture()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 3)
                                    .frame(width: 70, height: 70)

                                if cameraManager.isCapturing {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.red)
                                        .frame(width: 30, height: 30)
                                } else {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 60, height: 60)
                                }
                            }
                        }
                        .disabled(cameraManager.clipController.captureComplete)

                        // Export options appear when capture complete
                        if cameraManager.clipController.captureComplete {
                            HStack(spacing: 12) {
                                Button("Create GIF") {
                                    createGIF()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Export YXV") {
                                    exportYXV()
                                }
                                .buttonStyle(.bordered)

                                Button(action: {
                                    showVoxelViewer()
                                }) {
                                    Image(systemName: "cube")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                .padding()
            }
        }
        .onAppear {
            cameraManager.setupSession()
            // Note: pyramidLevel and paletteSize are set internally by CubeCameraManagerOptimized
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .sheet(isPresented: $showingGIF) {
            if let gif = generatedGIF {
                GIFPreviewSheet(gifData: gif)
            }
        }
        .sheet(isPresented: $showingVoxelViewer) {
            if let tensor = capturedTensor {
                VoxelViewerView(cubeTensor: tensor)
            }
        }
    }

    private func createGIF() {
        // Build tensor and encode to GIF using Rust FFI with optimized settings
        if let tensor = cameraManager.clipController.buildCubeTensor() {
            let dataModel = tensor.toCubeTensorData()
            capturedTensor = dataModel  // Store for voxel viewer
            
            // Use optimized delay for 256³: 33ms = 30fps playback, 40ms = 25fps
            let delayMs = (selectedN == 256) ? 33 : 40
            
            if let gif = GIF89aEncoder.encode(tensor: dataModel, delayMs: delayMs) {
                generatedGIF = gif
                showingGIF = true
            } else {
                print("GIF encoding failed.")
            }
        }
    }

    private func exportYXV() {
        // Export tensor to YXV format
        if let tensor = cameraManager.clipController.buildCubeTensor() {
            let dataModel = tensor.toCubeTensorData()
            capturedTensor = dataModel

            Task {
                // Create a temporary coordinator for export
                // In production, you'd inject this properly
                let coordinator = CaptureCoordinator()
                if let url = await coordinator.exportYXV(tensor: dataModel) {
                    print("YXV exported to: \(url)")
                    // Show share sheet or success message
                    shareFile(at: url)
                }
            }
        }
    }

    private func showVoxelViewer() {
        // Build tensor and show voxel viewer
        if let tensor = cameraManager.clipController.buildCubeTensor() {
            let dataModel = tensor.toCubeTensorData()
            capturedTensor = dataModel
            showingVoxelViewer = true
        }
    }

    private func shareFile(at url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        rootViewController.present(activityVC, animated: true)
    }
}

// Camera Preview Layer with no-crop behavior
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        // No crop: fit entire image; letterbox/pillarbox as needed.
        previewLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

// GIF preview sheet (reusing your earlier one)
struct GIFPreviewSheet: View {
    let gifData: Data
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                if let image = UIImage(data: gifData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }

                VStack(spacing: 4) {
                    let fileSizeMB = Double(gifData.count) / (1024 * 1024)
                    if fileSizeMB >= 1.0 {
                        Text(String(format: "%.2f MB", fileSizeMB))
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else {
                        Text("\(gifData.count / 1024) KB")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Text("256×256 • 256 frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 40) {
                    Button("Save") {
                        UIImageWriteToSavedPhotosAlbum(UIImage(data: gifData)!, nil, nil, nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Share") {
                        shareGIF()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("GIF Created")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }

    private func shareGIF() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [gifData], applicationActivities: nil)
        rootViewController.present(activityVC, animated: true)
    }
}
