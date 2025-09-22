//
//  VoxelCubeView.swift
//  RGB2GIF2VOXEL
//
//  3D Voxel Cube Visualization for GIF Tensor Data
//  Renders 16×16×256 tensor as interactive 3D sculpture
//

import SwiftUI
import SceneKit

// MARK: - SwiftUI View Wrapper

struct VoxelCubeView: UIViewRepresentable {

    // MARK: - Properties

    let tensorData: Data
    @Binding var isPlaying: Bool
    @Binding var playbackSpeed: Float
    @Binding var viewMode: VoxelDisplayMode

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .systemBackground
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true
        sceneView.showsStatistics = false

        // Create and set scene
        let renderer = context.coordinator
        sceneView.scene = renderer.createScene()
        sceneView.delegate = renderer

        // Configure rendering
        sceneView.rendersContinuously = true
        sceneView.preferredFramesPerSecond = 60

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.isAnimating = isPlaying
        context.coordinator.animationSpeed = playbackSpeed
        context.coordinator.updateViewMode(viewMode)
    }

    func makeCoordinator() -> VoxelCubeRenderer {
        VoxelCubeRenderer(tensorData: tensorData)
    }
}

// MARK: - View Modes

enum VoxelDisplayMode: String, CaseIterable {
    case solid = "Solid"
    case cloud = "Cloud"
    case slice = "Slice"
    case cross = "Cross-Section"

    var icon: String {
        switch self {
        case .solid: return "cube.fill"
        case .cloud: return "cloud.fill"
        case .slice: return "square.stack.3d.down.forward.fill"
        case .cross: return "scissors"
        }
    }
}

// MARK: - Voxel Renderer

class VoxelCubeRenderer: NSObject, SCNSceneRendererDelegate {

    // MARK: - Constants

    private let dimensions = (x: 16, y: 16, z: 256)
    private let voxelSize: CGFloat = 0.5
    private let voxelSpacing: CGFloat = 0.1

    // MARK: - Properties

    private let tensorData: Data
    private var rootNode: SCNNode!
    private var voxelContainer: SCNNode!
    private var voxelInstances: [VoxelInstance] = []
    private var currentZOffset: Float = 0.0
    private var lastUpdateTime: TimeInterval = 0

    var isAnimating = false
    var animationSpeed: Float = 1.0
    private var viewMode: VoxelDisplayMode = .solid

    // MARK: - Voxel Instance Structure

    struct VoxelInstance {
        let position: SCNVector3
        let color: UIColor
        let originalZ: Float
    }

    // MARK: - Initialization

    init(tensorData: Data) {
        self.tensorData = tensorData
        super.init()
        parseTensorData()
    }

    // MARK: - Scene Creation

    func createScene() -> SCNScene {
        let scene = SCNScene()
        rootNode = scene.rootNode

        // Create container for voxels
        voxelContainer = SCNNode()
        rootNode.addChildNode(voxelContainer)

        // Build voxel geometry based on view mode
        updateVoxelGeometry()

        // Setup lighting
        setupLighting()

        // Setup camera
        setupCamera()

        return scene
    }

    // MARK: - Tensor Parsing

    private func parseTensorData() {
        var offset = 0

        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    // Bounds check
                    guard offset + 3 < tensorData.count else { break }

                    // Extract RGBA
                    let r = CGFloat(tensorData[offset]) / 255.0
                    let g = CGFloat(tensorData[offset + 1]) / 255.0
                    let b = CGFloat(tensorData[offset + 2]) / 255.0
                    let a = CGFloat(tensorData[offset + 3]) / 255.0
                    offset += 4

                    // Skip mostly transparent voxels
                    if a < 0.1 { continue }

                    // Calculate position
                    let position = SCNVector3(
                        Float(x - dimensions.x/2) * Float(voxelSize + voxelSpacing),
                        Float(y - dimensions.y/2) * Float(voxelSize + voxelSpacing),
                        Float(z - dimensions.z/2) * Float(voxelSize + voxelSpacing)
                    )

                    // Store instance
                    let instance = VoxelInstance(
                        position: position,
                        color: UIColor(red: r, green: g, blue: b, alpha: a),
                        originalZ: Float(z)
                    )
                    voxelInstances.append(instance)
                }
            }
        }

        print("📊 Parsed \(voxelInstances.count) visible voxels from tensor")
    }

    // MARK: - Geometry Creation

    private func updateVoxelGeometry() {
        // Clear existing geometry
        voxelContainer.childNodes.forEach { $0.removeFromParentNode() }

        switch viewMode {
        case .solid:
            createSolidVoxels()
        case .cloud:
            createCloudVoxels()
        case .slice:
            createSliceView()
        case .cross:
            createCrossSectionView()
        }
    }

    private func createSolidVoxels() {
        // Create shared geometry
        let voxelGeometry = SCNBox(
            width: voxelSize,
            height: voxelSize,
            length: voxelSize,
            chamferRadius: voxelSize * 0.1
        )

        // Use instancing for performance
        for instance in voxelInstances {
            let node = SCNNode(geometry: voxelGeometry.copy() as? SCNGeometry)
            node.position = instance.position

            let material = SCNMaterial()
            material.diffuse.contents = instance.color
            material.transparency = instance.color.cgColor.alpha
            material.lightingModel = .physicallyBased
            node.geometry?.materials = [material]

            voxelContainer.addChildNode(node)
        }
    }

    private func createCloudVoxels() {
        // Create point cloud geometry
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []

        for instance in voxelInstances {
            vertices.append(instance.position)
            colors.append(instance.color)
        }

        // Create point cloud
        let pointGeometry = createPointCloud(vertices: vertices, colors: colors)
        let pointNode = SCNNode(geometry: pointGeometry)
        voxelContainer.addChildNode(pointNode)
    }

    private func createSliceView() {
        // Show only current Z-slice
        let currentSlice = Int(currentZOffset) % dimensions.z

        let voxelGeometry = SCNBox(
            width: voxelSize,
            height: voxelSize,
            length: voxelSize * 0.2, // Thin slice
            chamferRadius: 0
        )

        for instance in voxelInstances {
            let voxelZ = Int(instance.originalZ)
            if abs(voxelZ - currentSlice) <= 1 {
                let node = SCNNode(geometry: voxelGeometry.copy() as? SCNGeometry)
                node.position = instance.position

                let material = SCNMaterial()
                material.diffuse.contents = instance.color
                material.transparency = instance.color.cgColor.alpha
                material.isDoubleSided = true
                node.geometry?.materials = [material]

                voxelContainer.addChildNode(node)
            }
        }
    }

    private func createCrossSectionView() {
        // Create cutting plane through center
        let planeGeometry = SCNPlane(width: 20, height: 20)
        planeGeometry.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.1)
        planeGeometry.firstMaterial?.isDoubleSided = true

        let planeNode = SCNNode(geometry: planeGeometry)
        planeNode.eulerAngles = SCNVector3(0, Float.pi / 4, 0)
        voxelContainer.addChildNode(planeNode)

        // Show voxels near plane
        createSolidVoxels() // Start with all voxels
    }

    private func createPointCloud(vertices: [SCNVector3], colors: [UIColor]) -> SCNGeometry {
        // Create vertex source
        let vertexSource = SCNGeometrySource(vertices: vertices)

        // Create color source
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

        // Create point element
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

        element.pointSize = 5.0
        element.minimumPointScreenSpaceRadius = 2.0
        element.maximumPointScreenSpaceRadius = 10.0

        return SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
    }

    // MARK: - Lighting Setup

    private func setupLighting() {
        // Key light
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 800
        keyLight.light?.castsShadow = true
        keyLight.position = SCNVector3(20, 20, 20)
        keyLight.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(keyLight)

        // Fill light
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .omni
        fillLight.light?.intensity = 400
        fillLight.position = SCNVector3(-20, 10, 20)
        rootNode.addChildNode(fillLight)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 200
        ambientLight.light?.color = UIColor.systemGray
        rootNode.addChildNode(ambientLight)
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 45
        cameraNode.position = SCNVector3(30, 30, 30)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(cameraNode)
    }

    // MARK: - Animation

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isAnimating else { return }

        let deltaTime = lastUpdateTime == 0 ? 0 : time - lastUpdateTime
        lastUpdateTime = time

        // Update Z offset for conveyor animation
        currentZOffset += Float(deltaTime) * animationSpeed * 30.0

        // Wrap around
        if currentZOffset >= Float(dimensions.z) {
            currentZOffset -= Float(dimensions.z)
        }

        // Apply conveyor effect based on view mode
        if viewMode == .slice {
            // Update slice view
            DispatchQueue.main.async { [weak self] in
                self?.updateVoxelGeometry()
            }
        } else if viewMode == .solid || viewMode == .cloud {
            // Animate Z-axis scrolling
            animateConveyor()
        }
    }

    private func animateConveyor() {
        guard let container = voxelContainer else { return }

        // Rotate entire container for conveyor effect
        let rotation = SCNAction.rotateBy(
            x: 0,
            y: CGFloat(animationSpeed * 0.01),
            z: CGFloat(animationSpeed * 0.005),
            duration: 0.1
        )
        container.runAction(rotation)
    }

    // MARK: - View Mode Updates

    func updateViewMode(_ mode: VoxelDisplayMode) {
        guard mode != viewMode else { return }
        viewMode = mode

        DispatchQueue.main.async { [weak self] in
            self?.updateVoxelGeometry()
        }
    }
}