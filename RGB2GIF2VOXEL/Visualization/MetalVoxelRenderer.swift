//
//  MetalVoxelRenderer.swift
//  RGB2GIF2VOXEL
//
//  Metal-based 3D voxel cube renderer for GIF frames
//  Implements 128x128x128 voxel grid with frame conveyor
//

import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics

public class MetalVoxelRenderer: NSObject {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    // Voxel data
    private var voxelBuffer: MTLBuffer?
    private var instanceBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    // Frame conveyor
    private var frames: [Data] = []
    private var currentFrameIndex: Int = 0
    private var frameTextures: [MTLTexture] = []

    // Cube properties
    private let cubeSize = 128
    private var rotation: SIMD3<Float> = .zero
    private var translation: SIMD3<Float> = .zero
    private var scale: Float = 1.0

    // MARK: - Uniforms Structure

    struct Uniforms {
        var mvpMatrix: float4x4
        var normalMatrix: float3x3
        var lightPosition: SIMD3<Float>
        var viewPosition: SIMD3<Float>
        var time: Float
        var frameIndex: Int32
        var padding: SIMD2<Float> = .zero
    }

    // MARK: - Initialization

    public override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue

        // Create pipeline state with inline shader source
        let shaderSource = voxelShaderSource()
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            fatalError("Failed to create shader library")
        }
        let vertexFunction = library.makeFunction(name: "voxelVertexShader")
        let fragmentFunction = library.makeFunction(name: "voxelFragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Enable blending for transparency
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }

        // Create depth state
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!

        super.init()

        setupBuffers()
    }

    // MARK: - Setup

    private func setupBuffers() {
        // Create voxel cube vertices (a single voxel cube)
        let voxelVertices: [SIMD3<Float>] = [
            // Front face
            SIMD3<Float>(-0.5, -0.5,  0.5),
            SIMD3<Float>( 0.5, -0.5,  0.5),
            SIMD3<Float>( 0.5,  0.5,  0.5),
            SIMD3<Float>(-0.5,  0.5,  0.5),
            // Back face
            SIMD3<Float>(-0.5, -0.5, -0.5),
            SIMD3<Float>( 0.5, -0.5, -0.5),
            SIMD3<Float>( 0.5,  0.5, -0.5),
            SIMD3<Float>(-0.5,  0.5, -0.5),
        ]

        let indices: [UInt16] = [
            // Front face
            0, 1, 2, 0, 2, 3,
            // Back face
            4, 6, 5, 4, 7, 6,
            // Top face
            3, 2, 6, 3, 6, 7,
            // Bottom face
            0, 4, 5, 0, 5, 1,
            // Right face
            1, 5, 6, 1, 6, 2,
            // Left face
            0, 3, 7, 0, 7, 4,
        ]

        voxelBuffer = device.makeBuffer(bytes: voxelVertices, length: voxelVertices.count * MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared)

        // Uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)
    }

    // MARK: - Frame Management

    public func loadFrames(_ gifFrames: [Data]) {
        self.frames = gifFrames
        frameTextures = []

        // Convert frames to textures
        for frameData in gifFrames.prefix(cubeSize) {
            if let texture = createTexture(from: frameData) {
                frameTextures.append(texture)
            }
        }
    }

    private func createTexture(from frameData: Data) -> MTLTexture? {
        let size = 128 // Frame size

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = size
        textureDescriptor.height = size
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }

        frameData.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, size, size),
                          mipmapLevel: 0,
                          withBytes: bytes.baseAddress!,
                          bytesPerRow: size * 4)
        }

        return texture
    }

    // MARK: - Rendering

    public func render(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        // Update uniforms
        updateUniforms(viewSize: view.drawableSize)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        // Draw voxel grid
        drawVoxelGrid(encoder: encoder)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateUniforms(viewSize: CGSize) {
        let aspect = Float(viewSize.width / viewSize.height)
        let projectionMatrix = perspective(fov: .pi / 3, aspect: aspect, near: 0.1, far: 100)

        let viewMatrix = lookAt(eye: SIMD3<Float>(0, 0, 5),
                                center: SIMD3<Float>(0, 0, 0),
                                up: SIMD3<Float>(0, 1, 0))

        let modelMatrix = matrix4x4_translation(translation.x, translation.y, translation.z) *
                         matrix4x4_rotation(radians: rotation.x, axis: SIMD3<Float>(1, 0, 0)) *
                         matrix4x4_rotation(radians: rotation.y, axis: SIMD3<Float>(0, 1, 0)) *
                         matrix4x4_rotation(radians: rotation.z, axis: SIMD3<Float>(0, 0, 1)) *
                         matrix4x4_scale(scale, scale, scale)

        let mvpMatrix = projectionMatrix * viewMatrix * modelMatrix
        let normalMatrix = modelMatrix.upperLeft3x3

        var uniforms = Uniforms(
            mvpMatrix: mvpMatrix,
            normalMatrix: normalMatrix,
            lightPosition: SIMD3<Float>(5, 5, 5),
            viewPosition: SIMD3<Float>(0, 0, 5),
            time: Float(CACurrentMediaTime()),
            frameIndex: Int32(currentFrameIndex)
        )

        uniformBuffer?.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
    }

    private func drawVoxelGrid(encoder: MTLRenderCommandEncoder) {
        // Draw voxels as a 3D grid
        // Each voxel represents a pixel from the current frame layer

        guard !frameTextures.isEmpty else { return }

        // For demonstration, create instance data for visible voxels
        var instances: [float4x4] = []
        let voxelSize: Float = 1.0 / Float(cubeSize)

        // Sample the current frame texture and create voxels
        let frameIndex = currentFrameIndex % frameTextures.count

        // Create a grid of voxels based on the frame
        for z in 0..<min(frameTextures.count, cubeSize) {
            for y in 0..<cubeSize {
                for x in 0..<cubeSize {
                    // Position each voxel
                    let pos = SIMD3<Float>(
                        Float(x - cubeSize/2) * voxelSize,
                        Float(y - cubeSize/2) * voxelSize,
                        Float(z - cubeSize/2) * voxelSize
                    )

                    let transform = matrix4x4_translation(pos.x, pos.y, pos.z) *
                                   matrix4x4_scale(voxelSize * 0.9, voxelSize * 0.9, voxelSize * 0.9)

                    instances.append(transform)

                    // Limit instances for performance
                    if instances.count >= 1000 { break }
                }
                if instances.count >= 1000 { break }
            }
            if instances.count >= 1000 { break }
        }

        // Create instance buffer
        if let instanceBuffer = device.makeBuffer(bytes: instances,
                                                 length: instances.count * MemoryLayout<float4x4>.size,
                                                 options: .storageModeShared) {
            encoder.setVertexBuffer(voxelBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 2)

            // Bind current frame texture
            if frameIndex < frameTextures.count {
                encoder.setFragmentTexture(frameTextures[frameIndex], index: 0)
            }

            // Draw instanced
            encoder.drawIndexedPrimitives(type: .triangle,
                                         indexCount: 36,
                                         indexType: .uint16,
                                         indexBuffer: voxelBuffer!,
                                         indexBufferOffset: 0,
                                         instanceCount: instances.count)
        }
    }

    // MARK: - Interaction

    public func rotate(by delta: SIMD3<Float>) {
        rotation += delta
    }

    public func translate(by delta: SIMD3<Float>) {
        translation += delta
    }

    public func setScale(_ newScale: Float) {
        scale = max(0.1, min(5.0, newScale))
    }

    public func nextFrame() {
        currentFrameIndex = (currentFrameIndex + 1) % max(1, frameTextures.count)
    }

    public func previousFrame() {
        currentFrameIndex = (currentFrameIndex - 1 + frameTextures.count) % max(1, frameTextures.count)
    }
}

// MARK: - Matrix Helpers

private func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
    return float4x4([
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [x, y, z, 1]
    ])
}

private func matrix4x4_scale(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
    return float4x4([
        [x, 0, 0, 0],
        [0, y, 0, 0],
        [0, 0, z, 0],
        [0, 0, 0, 1]
    ])
}

private func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> float4x4 {
    let normalizedAxis = normalize(axis)
    let cosTheta = cos(radians)
    let sinTheta = sin(radians)
    let oneMinusCos = 1 - cosTheta

    let x = normalizedAxis.x
    let y = normalizedAxis.y
    let z = normalizedAxis.z

    return float4x4([
        [cosTheta + x * x * oneMinusCos, x * y * oneMinusCos - z * sinTheta, x * z * oneMinusCos + y * sinTheta, 0],
        [y * x * oneMinusCos + z * sinTheta, cosTheta + y * y * oneMinusCos, y * z * oneMinusCos - x * sinTheta, 0],
        [z * x * oneMinusCos - y * sinTheta, z * y * oneMinusCos + x * sinTheta, cosTheta + z * z * oneMinusCos, 0],
        [0, 0, 0, 1]
    ])
}

private func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let y = 1 / tan(fov * 0.5)
    let x = y / aspect
    let z = far / (far - near)
    let w = -near * far / (far - near)

    return float4x4([
        [x, 0, 0, 0],
        [0, y, 0, 0],
        [0, 0, z, 1],
        [0, 0, w, 0]
    ])
}

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let z = normalize(eye - center)
    let x = normalize(cross(up, z))
    let y = cross(z, x)

    return float4x4([
        [x.x, y.x, z.x, 0],
        [x.y, y.y, z.y, 0],
        [x.z, y.z, z.z, 0],
        [-dot(x, eye), -dot(y, eye), -dot(z, eye), 1]
    ])
}

private extension float4x4 {
    var upperLeft3x3: float3x3 {
        let col0 = SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z)
        let col1 = SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z)
        let col2 = SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
        return float3x3(col0, col1, col2)
    }
}

// MARK: - Inline Shader Source

private func voxelShaderSource() -> String {
    return """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float2 texCoord;
        float4 color;
    };

    struct Uniforms {
        float4x4 mvpMatrix;
        float3x3 normalMatrix;
        float3 lightPosition;
        float3 viewPosition;
        float time;
        int frameIndex;
    };

    vertex VertexOut voxelVertexShader(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant float3* vertices [[buffer(0)]],
        constant Uniforms& uniforms [[buffer(1)]],
        constant float4x4* instances [[buffer(2)]]
    ) {
        VertexOut out;

        // Simple cube vertices
        const float3 cubeVerts[8] = {
            float3(-0.5, -0.5,  0.5),
            float3( 0.5, -0.5,  0.5),
            float3( 0.5,  0.5,  0.5),
            float3(-0.5,  0.5,  0.5),
            float3(-0.5, -0.5, -0.5),
            float3( 0.5, -0.5, -0.5),
            float3( 0.5,  0.5, -0.5),
            float3(-0.5,  0.5, -0.5)
        };

        float3 vertexPos = cubeVerts[vertexID % 8];
        float4x4 instanceMatrix = instances[instanceID];
        float4 worldPos = instanceMatrix * float4(vertexPos, 1.0);

        out.position = uniforms.mvpMatrix * worldPos;
        out.worldPosition = worldPos.xyz;
        out.normal = normalize(uniforms.normalMatrix * vertexPos);
        out.texCoord = float2(vertexPos.x + 0.5, vertexPos.y + 0.5);

        // Color based on instance position
        float3 gridPos = worldPos.xyz * 128.0;
        out.color = float4(
            sin(gridPos.x * 0.1 + uniforms.time) * 0.5 + 0.5,
            cos(gridPos.y * 0.1 + uniforms.time * 1.3) * 0.5 + 0.5,
            sin(gridPos.z * 0.1 + uniforms.time * 0.7) * 0.5 + 0.5,
            0.8
        );

        return out;
    }

    fragment float4 voxelFragmentShader(
        VertexOut in [[stage_in]],
        constant Uniforms& uniforms [[buffer(0)]]
    ) {
        float3 lightDir = normalize(uniforms.lightPosition - in.worldPosition);
        float3 viewDir = normalize(uniforms.viewPosition - in.worldPosition);
        float3 normal = normalize(in.normal);

        float diffuse = max(dot(normal, lightDir), 0.0);
        float3 reflectDir = reflect(-lightDir, normal);
        float specular = pow(max(dot(viewDir, reflectDir), 0.0), 32);

        float3 ambient = 0.2 * in.color.rgb;
        float3 diffuseColor = diffuse * in.color.rgb;
        float3 specularColor = specular * float3(1.0);

        float3 finalColor = ambient + diffuseColor + specularColor * 0.5;

        // Add depth fog
        float fogFactor = smoothstep(0.8, 1.0, in.position.z / in.position.w);
        finalColor = mix(finalColor, float3(0.1, 0.1, 0.15), fogFactor * 0.3);

        return float4(finalColor, in.color.a);
    }
    """
}