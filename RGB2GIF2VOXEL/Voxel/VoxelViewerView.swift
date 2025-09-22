// VoxelViewerView.swift
// SwiftUI view for multi-view voxel rendering

import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct VoxelViewerView: View {
    @StateObject private var voxelEngine = VoxelRenderEngine()
    @State private var showExportMenu = false
    @State private var exportedURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var showError = false

    // For gesture control in 3D mode
    @State private var dragOffset = CGSize.zero
    @State private var accumulatedRotation = CGSize.zero

    // Injected tensor data
    let cubeTensor: CubeTensorData?

    init(cubeTensor: CubeTensorData? = nil) {
        self.cubeTensor = cubeTensor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Main content
                VStack(spacing: 0) {
                    // View mode selector
                    viewModeSelector
                        .padding()

                    // Render view
                    renderView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Controls
                    controlsView
                        .padding()
                }
            }
        }
        .onAppear {
            if let tensor = cubeTensor {
                voxelEngine.loadVoxelData(from: tensor)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
    }

    // MARK: - View Components

    private var viewModeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(VoxelViewMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.spring()) {
                            voxelEngine.currentViewMode = mode
                            if mode == .animated {
                                voxelEngine.startAnimation()
                            } else {
                                voxelEngine.stopAnimation()
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: mode.systemImage)
                                .font(.title2)
                            Text(mode.rawValue)
                                .font(.caption)
                        }
                        .foregroundColor(voxelEngine.currentViewMode == mode ? .white : .gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(voxelEngine.currentViewMode == mode ?
                                      Color.blue : Color.gray.opacity(0.2))
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var renderView: some View {
        ZStack {
            if let voxelData = voxelEngine.currentVoxelData {
                // Main render view
                VoxelSceneView(
                    voxelData: voxelData,
                    viewMode: voxelEngine.currentViewMode,
                    rotation: voxelEngine.rotation,
                    currentFrame: voxelEngine.currentFrame
                )
                .gesture(rotationGesture)

                // Frame counter for animated mode
                if voxelEngine.currentViewMode == .animated {
                    VStack {
                        HStack {
                            Text("Frame: \(voxelEngine.currentFrame + 1)/\(voxelData.dimensions.depth)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding()
                }

            } else {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "cube")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("No Voxel Data")
                        .font(.title2)
                        .foregroundColor(.gray)

                    Text("Capture a cube tensor to view")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
    }

    private var controlsView: some View {
        HStack(spacing: 20) {
            // Animation control
            if voxelEngine.currentViewMode == .animated {
                Button(action: {
                    voxelEngine.toggleAnimation()
                }) {
                    Image(systemName: voxelEngine.isAnimating ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Export button
            Button(action: {
                showExportMenu = true
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(voxelEngine.currentVoxelData == nil)
            .confirmationDialog("Export Format", isPresented: $showExportMenu) {
                Button("Export as USDZ") {
                    Task { await exportUSDZ() }
                }
                Button("Export as OBJ") {
                    Task { await exportOBJ() }
                }
                Button("Export as YXV") {
                    Task { await exportYXV() }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    // MARK: - Gestures

    private var rotationGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if voxelEngine.currentViewMode == .perspective {
                    let sensitivity: Float = 0.01
                    voxelEngine.rotation.x = Float(accumulatedRotation.height + value.translation.height) * sensitivity
                    voxelEngine.rotation.y = Float(accumulatedRotation.width + value.translation.width) * sensitivity
                }
            }
            .onEnded { value in
                if voxelEngine.currentViewMode == .perspective {
                    accumulatedRotation.width += value.translation.width
                    accumulatedRotation.height += value.translation.height
                }
            }
    }

    // MARK: - Export Functions

    private func exportUSDZ() async {
        do {
            if let url = try await voxelEngine.exportUSDZ() {
                exportedURL = url
                showShareSheet = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func exportOBJ() async {
        do {
            if let url = try await voxelEngine.exportOBJ() {
                exportedURL = url
                showShareSheet = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func exportYXV() async {
        guard let tensor = cubeTensor else { return }

        // Use the YXVIO extension we created
        let coordinator = CaptureCoordinator()
        if let url = await coordinator.exportYXV(tensor: tensor) {
            exportedURL = url
            showShareSheet = true
        }
    }
}

// MARK: - SceneKit View

struct VoxelSceneView: UIViewRepresentable {
    let voxelData: VoxelData
    let viewMode: VoxelViewMode
    let rotation: simd_float3
    let currentFrame: Int

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .black
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = viewMode == .perspective

        // Create scene
        let scene = SCNScene()
        sceneView.scene = scene

        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        scene.rootNode.addChildNode(cameraNode)

        // Add voxel geometry (placeholder)
        let voxelNode = createVoxelNode()
        scene.rootNode.addChildNode(voxelNode)

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        // Update based on view mode
        sceneView.allowsCameraControl = viewMode == .perspective

        // Update voxel display
        if let voxelNode = sceneView.scene?.rootNode.childNode(withName: "VoxelNode", recursively: true) {
            // Apply transform based on view mode
            let transform = VoxelRenderEngine().getTransformMatrix(for: viewMode)
            voxelNode.simdTransform = transform

            // Update for animation
            if viewMode == .animated {
                updateAnimatedFrame(voxelNode, frame: currentFrame)
            }
        }
    }

    private func createVoxelNode() -> SCNNode {
        // Create a placeholder cube for now
        // In production, this would generate actual voxel geometry
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.systemBlue

        let node = SCNNode(geometry: box)
        node.name = "VoxelNode"

        return node
    }

    private func updateAnimatedFrame(_ node: SCNNode, frame: Int) {
        // Update displayed frame
        // In production, this would show the actual frame slice
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct VoxelViewerView_Previews: PreviewProvider {
    static var previews: some View {
        VoxelViewerView()
    }
}