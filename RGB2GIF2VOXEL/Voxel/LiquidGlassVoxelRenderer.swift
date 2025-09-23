//
//  LiquidGlassVoxelRenderer.swift
//  RGB2GIF2VOXEL
//
//  Liquid Glass voxel renderer with 128-frame color palette (N=128 optimal)
//  Each frame contributes one color to the visualization
//

import SwiftUI
import SceneKit
import simd
import Combine

/// Liquid Glass Voxel Renderer with 128-color frame palette (N=128 optimal)
@MainActor
public class LiquidGlassVoxelRenderer: NSObject, ObservableObject, SCNSceneRendererDelegate {

    // MARK: - Published Properties
    @Published public var isRendering = false
    @Published public var visibleVoxelCount = 0
    @Published public var currentVisualizationMode: VisualizationMode = .liquidGlass
    @Published public var framePalette: [Color] = []

    // MARK: - Private Properties
    private let tensorData: Data
    private var rootNode: SCNNode!
    private var voxelContainer: SCNNode!
    private var glassContainer: SCNNode!
    private var frameColors: [UIColor] = []
    private var dominantColors: [UIColor] = []
    private var currentRotation: Float = 0

    // MARK: - Visualization Modes
    public enum VisualizationMode: String, CaseIterable {
        case liquidGlass = "Liquid Glass"
        case pointCloud = "Point Cloud"
        case volumetric = "Volumetric"
        case temporal = "Temporal Flow"
        case rainbow = "Rainbow Layers"

        var displayName: String { rawValue }

        var iconName: String {
            switch self {
            case .liquidGlass: return "drop.fill"
            case .pointCloud: return "circles.hexagongrid.fill"
            case .volumetric: return "cube.fill"
            case .temporal: return "timeline.selection"
            case .rainbow: return "rainbow"
            }
        }
    }

    // MARK: - Initialization

    public init(tensorData: Data) {
        self.tensorData = tensorData
        super.init()

        print("🌊 LiquidGlassVoxelRenderer initialized")
        print("   Tensor size: \(tensorData.count) bytes")
        print("   Expected for 128³: \(128*128*128*4) bytes")

        // Extract 128 colors (one per frame)
        extractFramePalette()
    }

    // MARK: - Color Palette Extraction

    private func extractFramePalette() {
        print("🎨 Extracting 128-color frame palette...")

        frameColors = []
        dominantColors = []

        let frameSize = 128 * 128 * 4
        let frameCount = min(128, tensorData.count / frameSize)

        for frameIndex in 0..<frameCount {
            let frameOffset = frameIndex * frameSize

            // Extract dominant color from this frame
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            var validPixelCount = 0

            // Sample the center region of the frame for dominant color
            for y in 36..<92 {  // Center 56x56 region (adjusted for 128x128)
                for x in 36..<92 {
                    let pixelOffset = frameOffset + (y * 128 + x) * 4

                    if pixelOffset + 3 < tensorData.count {
                        let alpha = CGFloat(tensorData[pixelOffset + 3]) / 255.0

                        if alpha > 0.1 {  // Only consider visible pixels
                            r += CGFloat(tensorData[pixelOffset]) / 255.0
                            g += CGFloat(tensorData[pixelOffset + 1]) / 255.0
                            b += CGFloat(tensorData[pixelOffset + 2]) / 255.0
                            validPixelCount += 1
                        }
                    }
                }
            }

            // Calculate average color for this frame
            if validPixelCount > 0 {
                r /= CGFloat(validPixelCount)
                g /= CGFloat(validPixelCount)
                b /= CGFloat(validPixelCount)

                // Boost saturation for more vibrant colors
                let color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                let enhanced = enhanceColorVibrancy(color)
                frameColors.append(enhanced)
                dominantColors.append(enhanced)
            } else {
                // Fallback to a gradient color if no valid pixels
                let hue = CGFloat(frameIndex) / CGFloat(frameCount)
                frameColors.append(UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0))
                dominantColors.append(UIColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1.0))
            }
        }

        // Convert to SwiftUI colors for published property
        framePalette = frameColors.map { Color($0) }

        print("   Extracted \(frameColors.count) frame colors")
        print("   First 5 colors: \(frameColors.prefix(5).map { colorToHex($0) })")
    }

    private func enhanceColorVibrancy(_ color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // Boost saturation and brightness
        s = min(1.0, s * 1.5)
        b = min(1.0, b * 1.2)

        return UIColor(hue: h, saturation: s, brightness: b, alpha: a)
    }

    private func colorToHex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    // MARK: - Scene Creation

    public func createScene() -> SCNScene {
        print("🎭 Creating Liquid Glass voxel scene...")

        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.02, alpha: 1.0)  // Very dark background
        rootNode = scene.rootNode

        // Main voxel container
        voxelContainer = SCNNode()
        rootNode.addChildNode(voxelContainer)

        // Glass effect container
        glassContainer = SCNNode()
        rootNode.addChildNode(glassContainer)

        // Build visualization
        switch currentVisualizationMode {
        case .liquidGlass:
            createLiquidGlassVoxels()
        case .pointCloud:
            createEnhancedPointCloud()
        case .volumetric:
            createVolumetricVoxels()
        case .temporal:
            createTemporalFlowVoxels()
        case .rainbow:
            createRainbowLayeredVoxels()
        }

        // Setup enhanced lighting
        setupLiquidGlassLighting()

        // Setup camera
        setupDynamicCamera()

        // Add glass overlays
        addLiquidGlassEffects()

        return scene
    }

    // MARK: - Liquid Glass Voxel Creation

    private func createLiquidGlassVoxels() {
        print("💧 Creating Liquid Glass voxels with frame palette...")

        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        var glassNodes: [SCNNode] = []

        // Phase 4: Start with lower density for first light
        let sampleStride = 8  // Reduced from 3 to 8 for < 200k points
        let frameSize = 128 * 128 * 4
        let frameCount = min(128, tensorData.count / frameSize)

        // Lower thresholds for visibility
        let alphaThreshold: CGFloat = 0.0  // Accept any non-zero alpha
        let lumaThreshold: CGFloat = 0.0   // Accept any non-zero RGB

        var nonTransparentCount = 0
        var totalChecked = 0

        for z in stride(from: 0, to: frameCount, by: sampleStride) {
            let frameOffset = z * frameSize
            let frameColor = frameColors[safe: z] ?? UIColor.white

            for y in stride(from: 0, to: 128, by: sampleStride) {
                for x in stride(from: 0, to: 128, by: sampleStride) {
                    let pixelOffset = frameOffset + (y * 128 + x) * 4

                    if pixelOffset + 3 < tensorData.count {
                        let r = CGFloat(tensorData[pixelOffset]) / 255.0
                        let g = CGFloat(tensorData[pixelOffset + 1]) / 255.0
                        let b = CGFloat(tensorData[pixelOffset + 2]) / 255.0
                        let a = CGFloat(tensorData[pixelOffset + 3]) / 255.0

                        // Use frame color modulated by pixel intensity
                        let intensity = (r + g + b) / 3.0
                        totalChecked += 1

                        // Phase 4: Lower thresholds - accept any non-zero for first light
                        if a > alphaThreshold || (r > 0 || g > 0 || b > 0) {
                            // Position in 3D space (centered around 64 for 128³ cube)
                            let position = SCNVector3(
                                Float(x - 64) * 0.2,
                                Float(y - 64) * 0.2,
                                Float(z - 64) * 0.2
                            )
                            vertices.append(position)

                            // Blend frame color with pixel color
                            var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0
                            frameColor.getRed(&fr, green: &fg, blue: &fb, alpha: nil)

                            let blendedColor = UIColor(
                                red: fr * 0.7 + r * 0.3,
                                green: fg * 0.7 + g * 0.3,
                                blue: fb * 0.7 + b * 0.3,
                                alpha: min(1.0, a * 1.5)
                            )
                            colors.append(blendedColor)

                            nonTransparentCount += 1

                            // Create glass spheres for high-intensity voxels
                            if intensity > 0.7 && glassNodes.count < 100 {
                                let glassSphere = createGlassSphere(
                                    at: position,
                                    color: frameColor,
                                    size: 1.0 + Float(intensity)
                                )
                                glassNodes.append(glassSphere)
                            }
                        }
                    }
                }
            }
        }

        // Phase 4: Enhanced logging for debugging
        print("   Total points checked: \(totalChecked)")
        print("   Non-transparent voxels found: \(nonTransparentCount)")
        print("   Final vertices for rendering: \(vertices.count)")
        print("   Glass nodes created: \(glassNodes.count)")
        print("   Sample stride used: \(sampleStride)")

        // Create point cloud
        if !vertices.isEmpty {
            let pointCloud = createLiquidPointCloud(vertices: vertices, colors: colors)
            voxelContainer.addChildNode(pointCloud)
            visibleVoxelCount = vertices.count
        }

        // Add glass spheres
        glassNodes.forEach { glassContainer.addChildNode($0) }

        // If no voxels, add debug visualization
        if vertices.isEmpty {
            print("⚠️ No visible voxels, adding debug rainbow cube...")
            addDebugRainbowCube()
        }
    }

    private func createGlassSphere(at position: SCNVector3, color: UIColor, size: Float) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(size))

        // Glass material with color tint
        sphere.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.3)
        sphere.firstMaterial?.specular.contents = UIColor.white
        sphere.firstMaterial?.emission.contents = color.withAlphaComponent(0.1)
        sphere.firstMaterial?.transparency = 0.7
        sphere.firstMaterial?.lightingModel = .physicallyBased
        sphere.firstMaterial?.metalness.contents = 0.1
        sphere.firstMaterial?.roughness.contents = 0.0

        let node = SCNNode(geometry: sphere)
        node.position = position

        // Add subtle animation
        let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 20)
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 1.1, duration: 2),
            SCNAction.scale(to: 1.0, duration: 2)
        ])
        node.runAction(SCNAction.repeatForever(SCNAction.group([rotation, pulse])))

        return node
    }

    private func createLiquidPointCloud(vertices: [SCNVector3], colors: [UIColor]) -> SCNNode {
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

        // Phase 4: Optimized point size settings for visibility
        element.pointSize = 6.0  // Base point size
        element.minimumPointScreenSpaceRadius = 2.0  // Min screen radius
        element.maximumPointScreenSpaceRadius = 10.0  // Max screen radius

        print("   Point cloud settings: size=6, minRadius=2, maxRadius=10")

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])

        // Add glow material
        geometry.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.2)
        geometry.firstMaterial?.lightingModel = .constant

        return SCNNode(geometry: geometry)
    }

    // MARK: - Alternative Visualization Modes

    private func createEnhancedPointCloud() {
        print("✨ Creating enhanced point cloud...")
        // Similar to liquid glass but without glass spheres
        createLiquidGlassVoxels()
    }

    private func createVolumetricVoxels() {
        print("📦 Creating volumetric voxels...")
        // Implementation would create solid cubes instead of points
    }

    private func createTemporalFlowVoxels() {
        print("⏱️ Creating temporal flow visualization...")
        // Implementation would show time progression through the Z axis
    }

    private func createRainbowLayeredVoxels() {
        print("🌈 Creating rainbow layered voxels...")
        // Implementation would create distinct colored layers for each frame
    }

    // MARK: - Liquid Glass Effects

    private func addLiquidGlassEffects() {
        // Add translucent glass panels for depth
        for i in 0..<5 {
            let plane = SCNPlane(width: 60, height: 60)
            plane.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.02)
            plane.firstMaterial?.transparency = 0.98
            plane.firstMaterial?.lightingModel = .physicallyBased

            let planeNode = SCNNode(geometry: plane)
            planeNode.position = SCNVector3(0, 0, Float(i - 2) * 10)
            planeNode.opacity = 0.1

            glassContainer.addChildNode(planeNode)
        }
    }

    // MARK: - Lighting

    private func setupLiquidGlassLighting() {
        // Key light with color from palette
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1200
        keyLight.light?.color = frameColors.first ?? UIColor.white
        keyLight.position = SCNVector3(30, 30, 30)
        keyLight.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(keyLight)

        // Fill light
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .omni
        fillLight.light?.intensity = 500
        fillLight.light?.color = frameColors[safe: 128] ?? UIColor.cyan
        fillLight.position = SCNVector3(-20, 10, 20)
        rootNode.addChildNode(fillLight)

        // Ambient with palette color
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        ambientLight.light?.color = frameColors.last ?? UIColor.purple
        rootNode.addChildNode(ambientLight)
    }

    private func setupDynamicCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 1000.0
        cameraNode.camera?.focalLength = 50
        cameraNode.camera?.focusDistance = 50
        cameraNode.camera?.wantsDepthOfField = true
        cameraNode.camera?.fStop = 5.6

        cameraNode.position = SCNVector3(50, 50, 50)
        cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(cameraNode)
    }

    // MARK: - Debug Visualization

    private func addDebugRainbowCube() {
        print("🌈 Adding debug rainbow cube...")

        for i in 0..<8 {
            let hue = CGFloat(i) / 8.0
            let color = UIColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)

            let cube = SCNBox(width: 5, height: 5, length: 5, chamferRadius: 0.5)
            cube.firstMaterial?.diffuse.contents = color
            cube.firstMaterial?.emission.contents = color.withAlphaComponent(0.3)

            let angle = Float(i) * .pi / 4.0
            let radius: Float = 15

            let node = SCNNode(geometry: cube)
            node.position = SCNVector3(
                cos(angle) * radius,
                sin(angle) * radius / 2,
                sin(angle) * radius
            )

            let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 10)
            node.runAction(SCNAction.repeatForever(rotation))

            voxelContainer.addChildNode(node)
        }

        print("   Added 8 rainbow debug cubes in a ring")
    }

    // MARK: - Animation

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isAnimating else { return }

        currentRotation += 0.01
        voxelContainer?.eulerAngles.y = currentRotation

        // Animate glass effects
        glassContainer?.opacity = CGFloat(0.5 + 0.3 * sin(currentRotation * 2))
    }

    // MARK: - Public Methods

    public func switchVisualizationMode(to mode: VisualizationMode) {
        print("🔄 Switching to \(mode.displayName) mode...")
        currentVisualizationMode = mode

        // Clear existing nodes
        voxelContainer?.enumerateChildNodes { (node, _) in
            node.removeFromParentNode()
        }
        glassContainer?.enumerateChildNodes { (node, _) in
            node.removeFromParentNode()
        }

        // Create new visualization
        switch mode {
        case .liquidGlass:
            createLiquidGlassVoxels()
            addLiquidGlassEffects()
        case .pointCloud:
            createEnhancedPointCloud()
        case .volumetric:
            createVolumetricVoxels()
        case .temporal:
            createTemporalFlowVoxels()
        case .rainbow:
            createRainbowLayeredVoxels()
        }
    }

    public var isAnimating = true
}

// MARK: - Helper Extensions

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}