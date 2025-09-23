import SwiftUI
import AVFoundation
import CoreMedia

struct CubeCameraView: View {
    @StateObject private var cameraManager = CubeCameraManagerOptimized()
    @StateObject private var paletteExtractor = GIFPaletteExtractor()  // Dynamic color extraction
    @State private var selectedN = 256 // Default to HD quality 256×256×256
    @State private var selectedPaletteSize = 256
    @State private var showingGIF = false
    @State private var generatedGIF: Data?
    @State private var showingVoxelViewer = false
    @State private var showingExportMenu = false
    @State private var capturedTensor: CubeTensorData?
    @State private var isCapturing = false

    // Updated options with 256×256×256 as primary target
    private let nOptions = [256, 132, 264]
    private let paletteOptions = [256, 128, 64]

    var body: some View {
        ZStack {
            // Dynamic gradient background using extracted colors
            DynamicGradientBackground(paletteExtractor: paletteExtractor)

            // Live camera preview in a square, no-crop container
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                CubeCameraPreviewLayer(session: cameraManager.session)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(paletteExtractor.dominantColor.opacity(0.5), lineWidth: 2)
                    )
                    .shadow(color: paletteExtractor.dominantColor.opacity(0.3), radius: 20)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .padding(20)

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
                        .liquidGlass(color: .red, intensity: 1.2)
                    }
                }
                .padding()

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    if cameraManager.isCapturing {
                        VStack(spacing: 8) {
                            // Use our beautiful gradient progress ring
                            GradientProgressRing(
                                progress: Double(cameraManager.clipController.captureProgress),
                                colors: paletteExtractor.animatedGradient.isEmpty ?
                                    [.yellow, .orange, .red] : paletteExtractor.animatedGradient
                            )
                            .frame(width: 80, height: 80)
                            
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

                    // Beautiful animated capture button with GIF colors
                    HStack(spacing: 16) {
                        AnimatedCaptureButton(
                            isCapturing: $isCapturing,
                            dominantColor: paletteExtractor.dominantColor,
                            action: {
                                if cameraManager.isCapturing {
                                    cameraManager.stopCapture()
                                    isCapturing = false
                                } else {
                                    cameraManager.startCapture()
                                    isCapturing = true
                                }
                            }
                        )
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
                .liquidGlass(color: paletteExtractor.dominantColor, intensity: 0.8)
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
            if let gif = generatedGIF, let tensor = capturedTensor {
                GIFPreviewSheet(gifData: gif, tensorData: tensor)
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

            // Process frames with Rust to get both GIF and full-resolution tensor
            Task {
                do {
                    // Get the raw RGBA data from the tensor's frames
                    // The frames contain the actual pixel data
                    let rgbaData = tensor.flatIndices()

                    // Configure Rust processing with tensor generation enabled
                    let quantizeOpts = FFIOptionsBuilder.buildQuantizeOpts(
                        qualityMin: 70,
                        qualityMax: 95,
                        speed: 5,
                        paletteSize: 256,
                        ditheringLevel: 0.8,
                        sharedPalette: true
                    )

                    let gifOpts = FFIOptionsBuilder.buildGifOpts(
                        width: 128,  // N=128 optimal
                        height: 128,
                        frameCount: tensor.frames.count,
                        fps: 30,
                        loopCount: 0,
                        optimize: true,
                        includeTensor: true  // CRITICAL: Generate full tensor!
                    )

                    // Call Rust processor
                    let result = try await Task.detached(priority: .userInitiated) {
                        try processAllFrames(
                            framesRgba: rgbaData,
                            width: 256,
                            height: 256,
                            frameCount: UInt32(tensor.frames.count),
                            quantizeOpts: quantizeOpts,
                            gifOpts: gifOpts
                        )
                    }.value

                    // Extract GIF and tensor from result
                    await MainActor.run {
                        generatedGIF = result.gifData
                        print("📦 GIF data generated: \(result.gifData.count) bytes")

                        // Store tensor for voxel viewer (raw RGBA data)
                        if let tensorData = result.tensorData {
                            // The tensor is already full 256×256×256 RGBA data
                            capturedTensor = CubeTensorData(
                                size: 256,
                                indices: [], // Not used for raw tensor
                                palette: [],  // Not used for raw tensor
                                paletteSize: 0,
                                rawTensorData: tensorData  // Use raw tensor from Rust
                            )

                            // Extract colors from the tensor for dynamic UI theming
                            paletteExtractor.extractFromRawTensor(tensorData)

                            print("✅ VOXEL TENSOR DATA READY FOR VISUALIZATION!")
                            print("   Size: \(tensorData.count) bytes")
                            print("   Expected: \(256*256*256*4) bytes")
                            print("   Match: \(tensorData.count == 256*256*256*4 ? "YES ✅" : "NO ❌")")
                            print("   The voxel cube button should now work!")
                            print("🎨 Extracted colors for dynamic UI theming")
                        } else {
                            print("❌ CRITICAL ERROR: No tensor data in ProcessResult!")
                            print("   The voxel cube button will NOT work!")
                            print("   Check that includeTensor is set to true in GifOpts")
                        }

                        showingGIF = true
                        print("📱 Showing GIF preview sheet with voxel cube button...")
                    }
                } catch {
                    print("Processing error: \(error)")
                }
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
struct CubeCameraPreviewLayer: UIViewRepresentable {
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

// GIF preview sheet with VOXEL CUBE button
struct GIFPreviewSheet: View {
    let gifData: Data
    let tensorData: CubeTensorData
    @Environment(\.dismiss) var dismiss
    @State private var showingVoxelCube = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // GIF Preview
                if let image = UIImage(data: gifData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 5)
                }

                // File info
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

                // VOXEL CUBE BUTTON - Prominent and easy to find!
                Button(action: {
                    print("🔮 VOXEL CUBE BUTTON PRESSED!")
                    print("   Tensor data available: \(tensorData.rawTensorData != nil ? "YES" : "NO")")
                    if let rawData = tensorData.rawTensorData {
                        print("   Raw tensor size: \(rawData.count) bytes")
                        print("   Expected size: \(256*256*256*4) bytes")
                        print("   Size match: \(rawData.count == 256*256*256*4 ? "YES ✅" : "NO ❌")")

                        // Check if data is not all zeros
                        let sample = rawData.prefix(1000)
                        let hasData = sample.contains { $0 != 0 }
                        print("   Contains non-zero data: \(hasData ? "YES ✅" : "NO ❌ - DATA IS EMPTY!")")

                        if !hasData {
                            print("❌ CRITICAL: Tensor data is all zeros!")
                            print("   The Rust code might not be properly generating the tensor.")
                        }
                    } else {
                        print("❌ ERROR: No raw tensor data available!")
                        print("   Cannot show voxel cube without tensor data.")
                    }
                    showingVoxelCube = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "cube.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View 256³ Voxel Cube")
                                .font(.headline)
                            Text("Inspect 3D temporal sculpture")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .purple.opacity(0.3), radius: 5)
                }
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 20) {
                    Button("Save GIF") {
                        UIImageWriteToSavedPhotosAlbum(UIImage(data: gifData)!, nil, nil, nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Share") {
                        shareGIF()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("GIF Created")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
            .fullScreenCover(isPresented: $showingVoxelCube) {
                // Convert tensor data to the format expected by VoxelVisualizationScreen
                VoxelVisualizationScreen(
                    gifData: gifData,
                    tensorData: convertTensorToVoxelData(tensorData)
                )
            }
        }
    }

    private func shareGIF() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [gifData], applicationActivities: nil)
        rootViewController.present(activityVC, animated: true)
    }

    // Convert CubeTensorData to raw Data for voxel visualization
    private func convertTensorToVoxelData(_ tensor: CubeTensorData) -> Data {
        // If we have raw tensor data from Rust, use that directly
        if let rawTensor = tensor.rawTensorData {
            print("✅ Using raw tensor data: \(rawTensor.count) bytes for voxel visualization")
            print("   Expected size for 256×256×256 RGBA: \(256*256*256*4) bytes")
            if rawTensor.count == 256*256*256*4 {
                print("   ✅ Tensor size is correct for full 256³ voxel cube!")
            } else {
                print("   ⚠️ Tensor size mismatch - voxel cube may not display correctly")
            }
            return rawTensor
        }

        print("⚠️ No raw tensor data available, falling back to indexed color conversion")

        // Otherwise, convert indexed color data to RGBA for visualization
        // tensor.size is N (e.g., 256) and we have N³ indices
        guard !tensor.indices.isEmpty && !tensor.palette.isEmpty else {
            print("❌ ERROR: No indices or palette available for conversion!")
            print("   This usually means the tensor wasn't properly generated.")
            // Return empty data that won't crash but will show nothing
            return Data(repeating: 0, count: 256*256*256*4)
        }

        var voxelData = Data()
        voxelData.reserveCapacity(tensor.indices.count * 4)

        // Convert each indexed color to RGBA
        for index in tensor.indices {
            let colorIndex = Int(index) % max(tensor.paletteSize, 1)
            if colorIndex < tensor.palette.count {
                let color = tensor.palette[colorIndex]

                // Extract RGBA components from UInt32
                let r = UInt8((color >> 24) & 0xFF)
                let g = UInt8((color >> 16) & 0xFF)
                let b = UInt8((color >> 8) & 0xFF)
                let a = UInt8(color & 0xFF)

                voxelData.append(r)
                voxelData.append(g)
                voxelData.append(b)
                voxelData.append(a)
            } else {
                // Fallback to black if index is out of bounds
                voxelData.append(contentsOf: [0, 0, 0, 255])
            }
        }

        print("✅ Converted \(tensor.indices.count) indexed colors to RGBA data")
        return voxelData
    }
}
