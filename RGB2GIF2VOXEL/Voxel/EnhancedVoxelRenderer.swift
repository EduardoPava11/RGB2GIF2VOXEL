//
//  EnhancedVoxelRenderer.swift
//  RGB2GIF2VOXEL
//
//  Beautiful voxel cube rendering with particle effects and dynamic lighting
//

import SwiftUI
import SceneKit
import simd

/// Enhanced voxel cube renderer with beautiful visual effects
class EnhancedVoxelRenderer: NSObject, SCNSceneRendererDelegate {
    private let tensorData: Data
    private var rootNode: SCNNode!
    private var voxelContainer: SCNNode!
    private var particleSystem: SCNParticleSystem?
    private var currentZOffset: Float = 0.0
    private var lastUpdateTime: TimeInterval = 0
    private var colorPalette: [UIColor] = []

    var isAnimating = true
    var currentMode: VisualizationMode = .pointCloud

    enum VisualizationMode: CaseIterable {
        case pointCloud
        case volumetric
        case layered
        case exploded
        case particles

        var displayName: String {
            switch self {
            case .pointCloud: return "Points"
            case .volumetric: return "Volume"
            case .layered: return "Layers"
            case .exploded: return "Exploded"
            case .particles: return "Particles"
            }
        }

        var iconName: String {
            switch self {
            case .pointCloud: return "circle.grid.3x3.fill"
            case .volumetric: return "cube.fill"
            case .layered: return "square.stack.3d.down.right.fill"
            case .exploded: return "cube.transparent"
            case .particles: return "sparkles"
            }
        }
    }

    init(tensorData: Data) {
        self.tensorData = tensorData
        super.init()
        extractColorPalette()
    }

    func switchVisualizationMode(to mode: VisualizationMode) {
        guard currentMode != mode else { return }
        currentMode = mode

        // Clear existing voxels
        voxelContainer?.enumerateChildNodes { (node, _) in
            node.removeFromParentNode()
        }

        // Create new visualization based on mode
        switch mode {
        case .pointCloud:
            createPointCloudVoxels()
        case .volumetric:
            createVolumetricVoxels()
        case .layered:
            createLayeredVisualization()
        case .exploded:
            createExplodedVoxels()
        case .particles:
            createParticleVoxels()
        }
    }

    func createScene() -> SCNScene {
        let scene = SCNScene()
        rootNode = scene.rootNode

        // Create main container
        voxelContainer = SCNNode()
        rootNode.addChildNode(voxelContainer)

        // Build voxel visualization based on mode
        switch currentMode {
        case .pointCloud:
            createEnhancedPointCloud()
        case .volumetric:
            createVolumetricRepresentation()
        case .layered:
            createLayeredVisualization()
        case .exploded:
            createExplodedView()
        case .particles:
            createParticleVoxels()
        }

        // Setup enhanced lighting
        setupDramaticLighting()

        // Add particle effects
        addParticleEffects()

        // Setup camera with better positioning
        setupCinematicCamera()

        // Add ambient effects
        addAmbientEffects(to: scene)

        return scene
    }

    // MARK: - Enhanced Point Cloud

    private func createEnhancedPointCloud() {
        print("🎨 Creating enhanced point cloud visualization...")

        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        var sizes: [CGFloat] = []

        let sampleStride = 4  // Higher density for beauty
        let frameSize = 256 * 256 * 4
        let frameCount = min(256, tensorData.count / frameSize)

        for z in Swift.stride(from: 0, to: frameCount, by: sampleStride) {
            let frameOffset = z * frameSize
            let depthFactor = Float(z) / Float(frameCount)

            for y in Swift.stride(from: 0, to: 256, by: sampleStride) {
                for x in Swift.stride(from: 0, to: 256, by: sampleStride) {
                    let pixelOffset = frameOffset + (y * 256 + x) * 4

                    if pixelOffset + 3 < tensorData.count {
                        let r = CGFloat(tensorData[pixelOffset]) / 255.0
                        let g = CGFloat(tensorData[pixelOffset + 1]) / 255.0
                        let b = CGFloat(tensorData[pixelOffset + 2]) / 255.0
                        let a = CGFloat(tensorData[pixelOffset + 3]) / 255.0

                        if a > 0.1 {
                            // Position with slight randomization for organic look
                            let jitter = Float.random(in: -0.5...0.5)
                            vertices.append(SCNVector3(
                                Float(x - 128) * 0.1 + jitter * 0.01,
                                Float(y - 128) * 0.1 + jitter * 0.01,
                                Float(z - 128) * 0.1 + jitter * 0.01
                            ))

                            // Enhance color based on depth
                            let enhancedColor = UIColor(
                                red: r * (1.0 + 0.2 * CGFloat(depthFactor)),
                                green: g * (1.0 + 0.1 * CGFloat(depthFactor)),
                                blue: b * (1.0 - 0.1 * CGFloat(depthFactor)),
                                alpha: a
                            )
                            colors.append(enhancedColor)

                            // Variable point sizes for depth
                            sizes.append(CGFloat(3.0 - depthFactor * 1.5))
                        }
                    }
                }
            }
        }

        // Create beautiful point cloud geometry
        let pointGeometry = createEnhancedPointGeometry(
            vertices: vertices,
            colors: colors,
            sizes: sizes
        )

        let pointNode = SCNNode(geometry: pointGeometry)
        voxelContainer.addChildNode(pointNode)

        // Add glow effect
        pointNode.geometry?.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.1)
        pointNode.geometry?.firstMaterial?.lightingModel = .constant

        print("✨ Created enhanced voxel cloud with \(vertices.count) points")
    }

    // MARK: - Additional visualization modes for switching

    private func createPointCloudVoxels() {
        createEnhancedPointCloud()
    }

    private func createVolumetricVoxels() {
        createVolumetricRepresentation()
    }

    private func createExplodedVoxels() {
        createExplodedView()
    }

    private func createParticleVoxels() {
        addParticleEffects()
    }

    // MARK: - Volumetric Representation

    private func createVolumetricRepresentation() {
        print("🌫️ Creating volumetric voxel representation...")

        // Create translucent boxes for voxel clusters
        let clusterSize = 32  // Group voxels into clusters
        let frameSize = 256 * 256 * 4

        for z in Swift.stride(from: 0, to: 256, by: clusterSize) {
            for y in Swift.stride(from: 0, to: 256, by: clusterSize) {
                for x in Swift.stride(from: 0, to: 256, by: clusterSize) {
                    // Sample cluster color
                    let centerPixel = z * frameSize + (y * 256 + x) * 4

                    if centerPixel + 3 < tensorData.count {
                        let r = CGFloat(tensorData[centerPixel]) / 255.0
                        let g = CGFloat(tensorData[centerPixel + 1]) / 255.0
                        let b = CGFloat(tensorData[centerPixel + 2]) / 255.0
                        let a = CGFloat(tensorData[centerPixel + 3]) / 255.0

                        if a > 0.1 {
                            let box = SCNBox(
                                width: CGFloat(clusterSize) * 0.08,
                                height: CGFloat(clusterSize) * 0.08,
                                length: CGFloat(clusterSize) * 0.08,
                                chamferRadius: 0.01
                            )

                            let material = SCNMaterial()
                            material.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 0.3)
                            material.emission.contents = UIColor(red: r, green: g, blue: b, alpha: 0.1)
                            material.transparency = 0.7
                            material.isDoubleSided = true
                            box.materials = [material]

                            let boxNode = SCNNode(geometry: box)
                            boxNode.position = SCNVector3(
                                Float(x - 128) * 0.1,
                                Float(y - 128) * 0.1,
                                Float(z - 128) * 0.1
                            )

                            voxelContainer.addChildNode(boxNode)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Layered Visualization

    private func createLayeredVisualization() {
        print("📚 Creating layered voxel visualization...")

        let layerCount = 16  // Show 16 key layers
        let layerSpacing = 256 / layerCount

        for layerIndex in 0..<layerCount {
            let z = layerIndex * layerSpacing
            let frameOffset = z * 256 * 256 * 4

            // Create plane for this layer
            let plane = SCNPlane(width: 25.6, height: 25.6)
            plane.cornerRadius = 1.0

            // Create image from layer data
            if let layerImage = createImageFromLayerData(at: frameOffset) {
                let material = SCNMaterial()
                material.diffuse.contents = layerImage
                material.emission.contents = layerImage
                material.emission.intensity = 0.3
                material.transparency = 0.8
                material.isDoubleSided = true
                plane.materials = [material]

                let planeNode = SCNNode(geometry: plane)
                planeNode.position = SCNVector3(0, 0, Float(z - 128) * 0.1)
                planeNode.opacity = 0.6

                voxelContainer.addChildNode(planeNode)
            }
        }
    }

    // MARK: - Exploded View

    private func createExplodedView() {
        print("💥 Creating exploded voxel view...")

        // Create expanding rings of voxels
        let ringCount = 8
        let voxelsPerRing = 32

        for ring in 0..<ringCount {
            let radius = Float(ring + 1) * 3.0
            let angleStep = 2.0 * Float.pi / Float(voxelsPerRing)

            for i in 0..<voxelsPerRing {
                let angle = Float(i) * angleStep
                let x = cos(angle) * radius
                let z = sin(angle) * radius

                // Sample color from data
                let sampleIndex = (ring * voxelsPerRing + i) * 256 * 4
                if sampleIndex + 3 < tensorData.count {
                    let r = CGFloat(tensorData[sampleIndex]) / 255.0
                    let g = CGFloat(tensorData[sampleIndex + 1]) / 255.0
                    let b = CGFloat(tensorData[sampleIndex + 2]) / 255.0

                    let sphere = SCNSphere(radius: 0.5)
                    let material = SCNMaterial()
                    material.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                    material.emission.contents = UIColor(red: r * 0.3, green: g * 0.3, blue: b * 0.3, alpha: 1.0)
                    sphere.materials = [material]

                    let sphereNode = SCNNode(geometry: sphere)
                    sphereNode.position = SCNVector3(x, Float(ring - 4) * 2, z)

                    voxelContainer.addChildNode(sphereNode)
                }
            }
        }
    }

    // MARK: - Enhanced Point Geometry

    private func createEnhancedPointGeometry(
        vertices: [SCNVector3],
        colors: [UIColor],
        sizes: [CGFloat]
    ) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(vertices: vertices)

        // Color data with enhanced alpha
        var colorData = Data()
        for color in colors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            colorData.append(contentsOf: [
                UInt8(r * 255),
                UInt8(g * 255),
                UInt8(b * 255),
                UInt8(min(255, a * 255 * 1.5))  // Enhance alpha for visibility
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

        // Create point elements
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

        // Enhanced point rendering
        element.pointSize = 4.0
        element.minimumPointScreenSpaceRadius = 2.0
        element.maximumPointScreenSpaceRadius = 8.0

        return SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
    }

    // MARK: - Lighting

    private func setupDramaticLighting() {
        // Key light with color from palette
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1200
        keyLight.light?.color = colorPalette.first ?? UIColor.white
        keyLight.light?.castsShadow = true
        keyLight.position = SCNVector3(20, 30, 20)
        keyLight.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(keyLight)

        // Fill light
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .omni
        fillLight.light?.intensity = 400
        fillLight.light?.color = colorPalette.last ?? UIColor.cyan
        fillLight.position = SCNVector3(-20, 10, -20)
        rootNode.addChildNode(fillLight)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        ambientLight.light?.color = UIColor(white: 0.9, alpha: 1.0)
        rootNode.addChildNode(ambientLight)
    }

    // MARK: - Camera

    private func setupCinematicCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 45
        cameraNode.camera?.focalLength = 50
        cameraNode.camera?.aperture = 0.3  // Depth of field
        cameraNode.camera?.wantsDepthOfField = true
        cameraNode.camera?.focusDistance = 50
        cameraNode.position = SCNVector3(35, 35, 35)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(cameraNode)
    }

    // MARK: - Effects

    private func addParticleEffects() {
        let particleSystem = SCNParticleSystem()
        particleSystem.birthRate = 50
        particleSystem.particleLifeSpan = 5
        particleSystem.particleSize = 0.1
        particleSystem.particleColor = colorPalette.randomElement() ?? .white
        particleSystem.emitterShape = SCNSphere(radius: 15)
        particleSystem.particleVelocity = 0.5
        particleSystem.particleVelocityVariation = 0.2
        particleSystem.loops = true

        let particleNode = SCNNode()
        particleNode.addParticleSystem(particleSystem)
        voxelContainer.addChildNode(particleNode)

        self.particleSystem = particleSystem
    }

    private func addAmbientEffects(to scene: SCNScene) {
        // Fog effect
        scene.fogStartDistance = 30
        scene.fogEndDistance = 60
        scene.fogColor = UIColor.black.withAlphaComponent(0.5)
        scene.fogDensityExponent = 1.0

        // Background gradient
        scene.background.contents = createGradientBackground()
    }

    // MARK: - Helper Methods

    private func extractColorPalette() {
        var colors: Set<UIColor> = []
        let sampleCount = 100

        for _ in 0..<sampleCount {
            let randomOffset = Int.random(in: 0..<(tensorData.count / 4)) * 4
            if randomOffset + 3 < tensorData.count {
                let r = CGFloat(tensorData[randomOffset]) / 255.0
                let g = CGFloat(tensorData[randomOffset + 1]) / 255.0
                let b = CGFloat(tensorData[randomOffset + 2]) / 255.0
                let a = CGFloat(tensorData[randomOffset + 3]) / 255.0

                if a > 0.5 {
                    colors.insert(UIColor(red: r, green: g, blue: b, alpha: 1.0))
                }
            }
        }

        colorPalette = Array(colors).prefix(10).map { $0 }
        print("🎨 Extracted \(colorPalette.count) unique colors for visualization")
    }

    private func createImageFromLayerData(at offset: Int) -> UIImage? {
        guard offset + 256 * 256 * 4 <= tensorData.count else { return nil }

        let width = 256
        let height = 256
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = offset + (y * width + x) * 4
                let dstIndex = (y * width + x) * 4

                if srcIndex + 3 < tensorData.count {
                    pixelData[dstIndex] = tensorData[srcIndex]      // R
                    pixelData[dstIndex + 1] = tensorData[srcIndex + 1]  // G
                    pixelData[dstIndex + 2] = tensorData[srcIndex + 2]  // B
                    pixelData[dstIndex + 3] = tensorData[srcIndex + 3]  // A
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func createGradientBackground() -> UIImage? {
        let size = CGSize(width: 512, height: 512)
        UIGraphicsBeginImageContext(size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        let colors = colorPalette.isEmpty
            ? [UIColor.black.cgColor, UIColor.darkGray.cgColor]
            : [colorPalette[0].withAlphaComponent(0.3).cgColor,
               UIColor.black.cgColor]

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0.0, 1.0]
        )!

        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: 0,
            endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
            endRadius: size.width,
            options: []
        )

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    // MARK: - Animation

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isAnimating else { return }

        let deltaTime = lastUpdateTime == 0 ? 0 : time - lastUpdateTime
        lastUpdateTime = time

        // Rotate container
        voxelContainer?.eulerAngles.y += Float(deltaTime) * 0.2

        // Pulse particle effects
        if let particles = particleSystem {
            particles.birthRate = CGFloat(50 + sin(Float(time)) * 20)
        }

        // Animate Z-offset for conveyor effect
        currentZOffset += Float(deltaTime) * 30.0
        if currentZOffset >= 256 {
            currentZOffset -= 256
        }
    }
}