//
//  VoxelVisualizationScreen.swift
//  RGB2GIF2VOXEL
//
//  Main screen for displaying and controlling the voxel cube visualization
//

import SwiftUI
import SceneKit
import Combine

struct VoxelVisualizationScreen: View {

    // MARK: - Properties

    let gifData: Data
    let tensorData: Data

    @StateObject private var paletteExtractor = GIFPaletteExtractor()
    @State private var isPlaying = true
    @State private var rotationAngle: Double = 0.0
    @State private var autoRotate = true
    @State private var visualizationMode: LiquidGlassVoxelRenderer.VisualizationMode = .liquidGlass

    @Environment(\.presentationMode) var presentationMode

    init(gifData: Data, tensorData: Data) {
        self.gifData = gifData
        self.tensorData = tensorData

        // Phase 3: Comprehensive tensor validation
        let expectedSize = 128 * 128 * 128 * 4  // 8,388,608 bytes (N=128 optimal)
        let isValidSize = tensorData.count == expectedSize

        // Compute checksum of first 1024 bytes
        var checksum: UInt32 = 0
        let checksumBytes = min(1024, tensorData.count)
        tensorData.prefix(checksumBytes).forEach { byte in
            checksum = checksum &+ UInt32(byte)
        }

        // Check for non-zero data
        let hasNonZeroData = tensorData.prefix(1024).contains { $0 != 0 }

        print("🎯 VoxelVisualizationScreen INITIALIZED!")
        print("   GIF bytes: \(gifData.count)")
        print("   Tensor bytes: \(tensorData.count)")
        print("   Expected bytes: \(expectedSize)")
        print("   Tensor valid: \(isValidSize ? "YES ✅" : "NO ❌")")
        print("   Checksum (first 1KB): \(checksum)")
        print("   Has non-zero data: \(hasNonZeroData ? "YES ✅" : "NO ❌")")

        if !isValidSize {
            print("   ⚠️ WARNING: Tensor size mismatch! Expected \(expectedSize), got \(tensorData.count)")
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dynamic gradient background using extracted GIF colors
            DynamicGradientBackground(paletteExtractor: paletteExtractor)

            VStack(spacing: 0) {
                // Header
                headerView

                // 3D Voxel Cube - THE MAIN ATTRACTION!
                voxelCubeView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Simplified Controls
                simplifiedControlsView
                    .padding()
                    .background(
                        BlurredBackground()
                            .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            VStack(spacing: 4) {
                Text("256³ VOXEL CUBE")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("16,777,216 voxels")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Empty space for balance
            Color.clear
                .frame(width: 28, height: 28)
        }
        .padding()
        .background(
            BlurredBackground()
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Voxel Cube View

    private var voxelCubeView: some View {
        GeometryReader { geometry in
            // Liquid Glass voxel cube with 256-frame palette
            LiquidGlassVoxelView(
                tensorData: tensorData,
                isPlaying: $isPlaying,
                visualizationMode: $visualizationMode,
                paletteColors: paletteExtractor.extractedPalette
            )
            .rotation3DEffect(
                .degrees(rotationAngle),
                axis: (x: 0.3, y: 1, z: 0)  // Slight tilt for better visibility
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        autoRotate = false
                        rotationAngle += Double(value.translation.width) / 3.0
                    }
            )
            .onTapGesture {
                withAnimation(.spring()) {
                    isPlaying.toggle()
                }
            }
            .onAppear {
                // Extract colors from tensor
                paletteExtractor.extractFromRawTensor(tensorData)

                // Auto-rotate the cube
                if autoRotate {
                    withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                        rotationAngle = 360
                    }
                }
            }
        }
    }

    // MARK: - Simplified Controls

    private var simplifiedControlsView: some View {
        VStack(spacing: 15) {
            // Visualization mode selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(LiquidGlassVoxelRenderer.VisualizationMode.allCases, id: \.self) { mode in
                        Button(action: {
                            withAnimation(.spring()) {
                                visualizationMode = mode
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 22))
                                Text(mode.displayName)
                                    .font(.caption2)
                            }
                            .foregroundColor(visualizationMode == mode ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .liquidGlass(
                                color: visualizationMode == mode ? paletteExtractor.dominantColor : .white,
                                intensity: visualizationMode == mode ? 1.0 : 0.3
                            )
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Play/Pause and rotation control
            HStack(spacing: 40) {
                // Play/Pause the conveyor animation
                Button(action: {
                    withAnimation(.spring()) {
                        isPlaying.toggle()
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)

                        Text(isPlaying ? "Pause" : "Play")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                // Auto-rotate toggle
                Button(action: {
                    autoRotate.toggle()
                    if autoRotate {
                        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                            rotationAngle += 360
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: autoRotate ? "rotate.3d.fill" : "rotate.3d")
                            .font(.system(size: 44))
                            .foregroundColor(.white)

                        Text(autoRotate ? "Rotating" : "Rotate")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }

            // Info text
            VStack(spacing: 4) {
                Text("Drag to rotate • Tap to play/pause")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                Text("Z-axis shows time progression")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            // Share button
            Button(action: {
                shareGIF()
            }) {
                Label("Share GIF", systemImage: "square.and.arrow.up")
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.white.opacity(0.2))
                    )
            }
        }
    }

    // MARK: - Actions

    private func shareGIF() {
        let activityVC = UIActivityViewController(
            activityItems: [gifData],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Liquid Glass Voxel View

struct LiquidGlassVoxelView: UIViewRepresentable {
    let tensorData: Data
    @Binding var isPlaying: Bool
    @Binding var visualizationMode: LiquidGlassVoxelRenderer.VisualizationMode
    let paletteColors: [Color]

    func makeUIView(context: Context) -> SCNView {
        print("🎆 Creating SCNView for voxel visualization...")
        let sceneView = SCNView()
        sceneView.backgroundColor = .black  // Black background for better contrast
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true
        sceneView.showsStatistics = true  // Show FPS and other stats for debugging
        sceneView.antialiasingMode = .multisampling4X

        // Create scene with enhanced renderer
        let renderer = context.coordinator
        sceneView.scene = renderer.createScene()
        sceneView.delegate = renderer

        // Enable continuous rendering for animation
        sceneView.rendersContinuously = true
        sceneView.preferredFramesPerSecond = 60

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.isAnimating = isPlaying
        if context.coordinator.currentVisualizationMode != visualizationMode {
            context.coordinator.switchVisualizationMode(to: visualizationMode)
        }
    }

    func makeCoordinator() -> LiquidGlassVoxelRenderer {
        LiquidGlassVoxelRenderer(tensorData: tensorData)
    }
}

// MARK: - Simplified Voxel Cube View for 256×256×256 (kept for backwards compatibility)

struct SimplifiedVoxelCubeView: UIViewRepresentable {
    let tensorData: Data
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true
        sceneView.showsStatistics = false

        // Create scene with simplified renderer
        let renderer = context.coordinator
        sceneView.scene = renderer.createScene()
        sceneView.delegate = renderer

        // Enable continuous rendering for animation
        sceneView.rendersContinuously = true
        sceneView.preferredFramesPerSecond = 60

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.isAnimating = isPlaying
    }

    func makeCoordinator() -> SimplifiedVoxelRenderer {
        SimplifiedVoxelRenderer(tensorData: tensorData)
    }
}

// Simplified renderer focusing on 256×256×256 visualization
class SimplifiedVoxelRenderer: NSObject, SCNSceneRendererDelegate {
    private let tensorData: Data
    private var rootNode: SCNNode!
    private var voxelContainer: SCNNode!
    private var currentZOffset: Float = 0.0
    private var lastUpdateTime: TimeInterval = 0

    var isAnimating = true

    init(tensorData: Data) {
        self.tensorData = tensorData
        super.init()
    }

    func createScene() -> SCNScene {
        print("🌌 Creating voxel scene...")
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.05, alpha: 1.0)  // Very dark gray background
        rootNode = scene.rootNode

        // Create container
        voxelContainer = SCNNode()
        rootNode.addChildNode(voxelContainer)

        // Build simplified voxel geometry
        createVoxelCloud()

        // Setup lighting
        setupLighting()

        // Setup camera
        setupCamera()

        return scene
    }

    private func createVoxelCloud() {
        print("🔨 Creating voxel cloud from tensor data...")
        print("   Tensor data size: \(tensorData.count) bytes")
        print("   Expected size for 256³: \(256*256*256*4) bytes")
        print("   Size match: \(tensorData.count == 256*256*256*4 ? "YES ✅" : "NO ❌")")

        // Verify tensor data is not all zeros
        let firstBytes = tensorData.prefix(100)
        let hasNonZeroData = firstBytes.contains { $0 != 0 }
        print("   Has non-zero data: \(hasNonZeroData ? "YES ✅" : "NO ❌ (tensor is all zeros!)")")

        if !hasNonZeroData {
            print("❌ CRITICAL: Tensor data is all zeros! The voxel cube cannot be rendered.")
            print("   This means the tensor wasn't properly generated from Rust.")
        }

        // For 256×256×256, we'll sample and create a point cloud
        // to visualize the full cube efficiently
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []

        let sampleStride = 4  // Sample every 4th voxel for MORE visibility
        let frameSize = 256 * 256 * 4
        let frameCount = min(256, tensorData.count / frameSize)

        print("   Frame size: \(frameSize) bytes")
        print("   Frame count: \(frameCount)")
        print("   Sample stride: \(sampleStride) (showing 1 in every \(sampleStride) voxels)")

        var nonTransparentCount = 0
        var transparentCount = 0

        for z in Swift.stride(from: 0, to: frameCount, by: sampleStride) {
            let frameOffset = z * frameSize

            for y in Swift.stride(from: 0, to: 256, by: sampleStride) {
                for x in Swift.stride(from: 0, to: 256, by: sampleStride) {
                    let pixelOffset = frameOffset + (y * 256 + x) * 4

                    if pixelOffset + 3 < tensorData.count {
                        let r = CGFloat(tensorData[pixelOffset]) / 255.0
                        let g = CGFloat(tensorData[pixelOffset + 1]) / 255.0
                        let b = CGFloat(tensorData[pixelOffset + 2]) / 255.0
                        let a = CGFloat(tensorData[pixelOffset + 3]) / 255.0

                        // Lower threshold to catch more voxels
                        if a > 0.01 || (r + g + b) > 0.1 {  // Show voxels with any color or minimal alpha
                            vertices.append(SCNVector3(
                                Float(x - 128) * 0.15,  // Slightly larger scale
                                Float(y - 128) * 0.15,
                                Float(z - 128) * 0.15
                            ))
                            // Boost alpha for better visibility
                            let boostedAlpha = min(1.0, a * 2.0)
                            colors.append(UIColor(red: r, green: g, blue: b, alpha: boostedAlpha))
                            nonTransparentCount += 1
                        } else {
                            transparentCount += 1
                        }
                    }
                }
            }
        }

        print("   Non-transparent voxels: \(nonTransparentCount)")
        print("   Transparent voxels skipped: \(transparentCount)")

        // Create point cloud geometry
        if vertices.isEmpty {
            print("❌ ERROR: No visible voxels to display!")
            print("   This means the tensor data might be all zeros or all transparent")
            print("   Creating debug cube to verify rendering works...")

            // Add a debug cube so we can at least see something
            createDebugCube()
        } else {
            let pointGeometry = createPointCloud(vertices: vertices, colors: colors)
            let pointNode = SCNNode(geometry: pointGeometry)
            voxelContainer.addChildNode(pointNode)

            print("✅ Created voxel cloud with \(vertices.count) visible points!")
            print("   The 256³ voxel cube should now be visible!")
            print("   If you still can't see it, check:")
            print("   - Camera position and orientation")
            print("   - Point size and rendering settings")
            print("   - View background (points might be same color as background)")
        }
    }

    private func createPointCloud(vertices: [SCNVector3], colors: [UIColor]) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(vertices: vertices)

        var colorData = Data()
        for color in colors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            colorData.append(contentsOf: [
                UInt8(r * 255),
                UInt8(g * 255),
                UInt8(b * 255),
                UInt8(a * 255)
            ])
        }

        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: 1,
            dataOffset: 0,
            dataStride: 4
        )

        var indices: [Int32] = []
        for i in 0..<vertices.count {
            indices.append(Int32(i))
        }

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        element.pointSize = 5.0  // Larger points for better visibility
        element.minimumPointScreenSpaceRadius = 2.0
        element.maximumPointScreenSpaceRadius = 10.0

        return SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
    }

    private func createDebugCube() {
        print("🧊 Creating debug cube to verify SceneKit rendering...")

        // Create a simple colored cube mesh for debugging
        let cubeGeometry = SCNBox(width: 10, height: 10, length: 10, chamferRadius: 0.5)
        cubeGeometry.firstMaterial?.diffuse.contents = UIColor.systemPurple
        cubeGeometry.firstMaterial?.specular.contents = UIColor.white
        cubeGeometry.firstMaterial?.emission.contents = UIColor.purple.withAlphaComponent(0.3)

        let debugNode = SCNNode(geometry: cubeGeometry)
        debugNode.position = SCNVector3(0, 0, 0)

        // Add rotation animation so we know it's rendering
        let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 10)
        let repeatRotation = SCNAction.repeatForever(rotation)
        debugNode.runAction(repeatRotation)

        voxelContainer.addChildNode(debugNode)

        print("   Debug cube added at origin with rotation animation")
        print("   If you see a rotating purple cube, SceneKit is working!")
        print("   If not, there's a rendering issue with the view itself.")
    }

    private func setupLighting() {
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1000
        keyLight.position = SCNVector3(20, 20, 20)
        keyLight.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(keyLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 400
        rootNode.addChildNode(ambientLight)
    }

    private func setupCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60  // Wider field of view
        cameraNode.camera?.usesOrthographicProjection = false
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 1000.0

        // Position camera further back to see the whole cube
        cameraNode.position = SCNVector3(60, 60, 60)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(cameraNode)

        print("📷 Camera setup complete:")
        print("   Position: (60, 60, 60)")
        print("   Looking at: origin (0, 0, 0)")
        print("   Field of view: 60°")
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isAnimating else { return }

        let deltaTime = lastUpdateTime == 0 ? 0 : time - lastUpdateTime
        lastUpdateTime = time

        // Animate conveyor effect
        currentZOffset += Float(deltaTime) * 30.0
        if currentZOffset >= 256 {
            currentZOffset -= 256
        }

        // Rotate container for visual effect
        DispatchQueue.main.async { [weak self] in
            self?.voxelContainer?.eulerAngles.z = Float(self?.currentZOffset ?? 0) * 0.001
        }
    }
}

// MARK: - Supporting Views

struct BlurredBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}