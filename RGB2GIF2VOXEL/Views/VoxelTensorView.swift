//
//  VoxelTensorView.swift
//  RGB2GIF2VOXEL
//
//  Voxel tensor visualization with 2D conveyor and 3D rendering
//

import SwiftUI
import MetalKit
import simd
import CoreGraphics
import Combine

public struct VoxelTensorView: View {
    let tensorData: Data
    let gifData: Data?

    @State private var currentSlice = 0
    @State private var isAnimating = true
    @State private var show3D = false
    @State private var rotation = SIMD3<Float>(0, 0, 0)

    @State private var saveConfirmation: String?
    @State private var showSaveAlert = false

    private let side = 128
    private let bytesPerPixel = 4

    private let sliceTimer = Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()

    public init(tensorData: Data, gifData: Data?) {
        self.tensorData = tensorData
        self.gifData = gifData
    }

    public var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.black, .purple.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                // Header
                headerView

                // Visualization
                if show3D {
                    // 3D voxel view
                    Simple3DVoxelView(tensorData: tensorData, rotation: $rotation, side: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 2D conveyor view
                    conveyorView
                }

                // Controls
                controlsView
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(sliceTimer) { _ in
            if isAnimating && !show3D {
                currentSlice = (currentSlice + 1) % side
            }
        }
        .alert("Tensor Saved", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveConfirmation ?? "")
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("VOXEL TENSOR")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            let expectedBytes = side * side * side * bytesPerPixel
            let ok = tensorData.count == expectedBytes
            Text("128×128×128×4 (\(tensorData.count / 1024 / 1024) MB) \(ok ? "✓" : "⚠︎")")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(ok ? .green.opacity(0.8) : .yellow.opacity(0.9))

            if !show3D {
                Text("Z: \(currentSlice)/\(side - 1)")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            // Save tensor button for confirmation and persistence
            HStack(spacing: 12) {
                Button {
                    saveTensorToDisk()
                } label: {
                    Label("Save 128³ Tensor", systemImage: "externaldrive.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.7)))
                        .foregroundColor(.white)
                }

                if let gifData, !gifData.isEmpty {
                    ShareLink(item: gifData, preview: SharePreview("GIF89a", image: Image(systemName: "photo"))) {
                        Label("Share GIF", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.purple.opacity(0.7)))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding()
    }

    private var conveyorView: some View {
        VStack(spacing: 20) {
            // Current slice image
            if let sliceImage = extractSliceImage(at: currentSlice) {
                Image(uiImage: sliceImage)
                    .resizable()
                    .interpolation(.none)  // Pixelated look
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 400)
                    .background(Color.black)
                    .cornerRadius(12)
                    .shadow(color: .purple.opacity(0.5), radius: 20)
            } else {
                Text("Slice unavailable (size mismatch?)")
                    .foregroundColor(.yellow)
            }

            // Slice scrubber
            VStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(currentSlice) },
                    set: { currentSlice = Int($0) }
                ), in: 0...Double(side - 1), step: 1)
                    .accentColor(.purple)
                    .disabled(isAnimating)

                Text("Frame \(currentSlice)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal)
        }
    }

    private var controlsView: some View {
        VStack(spacing: 16) {
            if !show3D {
                // Animation control
                Button(action: { isAnimating.toggle() }) {
                    Label(
                        isAnimating ? "Pause" : "Play",
                        systemImage: isAnimating ? "pause.fill" : "play.fill"
                    )
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(isAnimating ? Color.orange : Color.green)
                    )
                }
            }

            // Toggle 2D/3D view
            Button(action: { withAnimation { show3D.toggle() } }) {
                Label(
                    show3D ? "2D Conveyor" : "3D Voxel",
                    systemImage: show3D ? "square.stack" : "cube.fill"
                )
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.purple)
                )
            }

            // Close button (host view should handle dismissal)
            Button(action: { /* Dismiss from host */ }) {
                Text("Close")
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
        .padding()
    }

    // Extract a 2D slice from the 3D tensor
    private func extractSliceImage(at z: Int) -> UIImage? {
        let frameSize = side
        let bytesPerSlice = frameSize * frameSize * bytesPerPixel

        let startIndex = z * bytesPerSlice
        let endIndex = startIndex + bytesPerSlice

        guard startIndex >= 0,
              endIndex <= tensorData.count else { return nil }

        let sliceData = tensorData.subdata(in: startIndex..<endIndex)

        // Create CGImage from slice data (BGRA, sRGB, premultipliedFirst)
        guard let cgImage = createCGImage(from: sliceData) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func createCGImage(from data: Data) -> CGImage? {
        let bytesPerRow = side * bytesPerPixel

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func saveTensorToDisk() {
        let expectedBytes = side * side * side * bytesPerPixel
        guard tensorData.count == expectedBytes else {
            saveConfirmation = "Size mismatch. Expected \(expectedBytes) bytes, got \(tensorData.count)."
            showSaveAlert = true
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxel_tensor_\(Int(Date().timeIntervalSince1970)).bin")
        do {
            try tensorData.write(to: url, options: .atomic)
            saveConfirmation = "Saved 128×128×128×4 tensor (\(tensorData.count) bytes) to:\n\(url.path)"
        } catch {
            saveConfirmation = "Failed to save tensor: \(error.localizedDescription)"
        }
        showSaveAlert = true
    }
}

// MARK: - Simple 3D Voxel View

struct Simple3DVoxelView: UIViewRepresentable {
    let tensorData: Data
    @Binding var rotation: SIMD3<Float>
    let side: Int

    func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = 30

        // Setup simple renderer
        if let device = metalView.device {
            context.coordinator.setupRenderer(device: device, tensorData: tensorData, side: side)
            metalView.delegate = context.coordinator
        }

        // Add gesture recognizer
        let gesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        metalView.addGestureRecognizer(gesture)

        return metalView
    }

    func updateUIView(_ metalView: MTKView, context: Context) {
        context.coordinator.rotation = rotation
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: Simple3DVoxelView
        var rotation = SIMD3<Float>(0, 0, 0)
        private var renderer: SimpleVoxelRenderer?

        init(_ parent: Simple3DVoxelView) {
            self.parent = parent
            super.init()
        }

        func setupRenderer(device: MTLDevice, tensorData: Data, side: Int) {
            renderer = SimpleVoxelRenderer(device: device, tensorData: tensorData, side: side)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize if needed
        }

        func draw(in view: MTKView) {
            renderer?.rotation = rotation
            renderer?.render(in: view)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            rotation.y += Float(translation.x) * 0.01
            rotation.x += Float(translation.y) * 0.01
            gesture.setTranslation(.zero, in: gesture.view)
            parent.rotation = rotation
        }
    }
}

// MARK: - Simple Voxel Renderer

class SimpleVoxelRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let tensorData: Data
    private let side: Int
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var voxelTexture: MTLTexture?

    // Decimation stride for instancing (draw every Nth voxel per axis)
    private let stridePerAxis: Int = 4

    var rotation = SIMD3<Float>(0, 0, 0)
    private var time: Float = 0

    init(device: MTLDevice, tensorData: Data, side: Int) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.tensorData = tensorData
        self.side = side
        setupPipeline()
        setupGeometry()
        setupVoxelTexture()
    }

    private func setupPipeline() {
        // Metal shader source
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vertex {
            float3 position [[attribute(0)]];
        };

        struct Uniforms {
            float4x4 modelMatrix;
            float4x4 viewMatrix;
            float4x4 projectionMatrix;
            float time;
            uint gridSize;   // 128
            uint stride;     // e.g. 4
            uint gridDiv;    // gridSize / stride
            float alphaThreshold;
        };

        struct VertexOut {
            float4 position [[position]];
            float3 voxelCoord;
            float3 color;
        };

        vertex VertexOut vertex_voxel(
            Vertex in [[stage_in]],
            constant Uniforms& uniforms [[buffer(1)]],
            uint instanceID [[instance_id]]
        ) {
            // Map compact instanceID (0..gridDiv^3-1) -> voxelPos in full grid (step=stride)
            uint gx = uniforms.gridDiv;
            uint gy = uniforms.gridDiv;
            uint gz = uniforms.gridDiv;

            uint iz = instanceID / (gx * gy);
            uint rem = instanceID % (gx * gy);
            uint iy = rem / gx;
            uint ix = rem % gx;

            uint3 voxelPos = uint3(ix * uniforms.stride,
                                   iy * uniforms.stride,
                                   iz * uniforms.stride);

            // Scale and center the grid
            float3 centered = (float3(voxelPos) - float3(uniforms.gridSize) * 0.5) * 0.02 + in.position * 0.01;

            // Apply transformations
            float4 position = float4(centered, 1.0);
            position = uniforms.modelMatrix * position;
            position = uniforms.viewMatrix * position;
            position = uniforms.projectionMatrix * position;

            VertexOut out;
            out.position = position;
            out.voxelCoord = (float3(voxelPos) + 0.5) / float(uniforms.gridSize);

            // Position-based color for variety
            float frameColor = float(voxelPos.z) / float(uniforms.gridSize);
            out.color = mix(float3(0.2, 0.6, 1.0), float3(1.0, 0.3, 0.8), frameColor);

            return out;
        }

        fragment float4 fragment_voxel(
            VertexOut in [[stage_in]],
            texture3d<float> voxelData [[texture(0)]],
            constant Uniforms& uniforms [[buffer(1)]]
        ) {
            constexpr sampler s(coord::normalized, filter::nearest);
            float4 c = voxelData.sample(s, in.voxelCoord);

            // Many camera-derived tensors have alpha=0; derive visibility from luminance if needed.
            float luma = dot(c.rgb, float3(0.2126, 0.7152, 0.0722));
            float a = max(c.a, luma);

            if (a < uniforms.alphaThreshold) {
                discard_fragment();
            }

            float3 finalColor = mix(in.color, c.rgb, 0.7);
            return float4(finalColor, a);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "vertex_voxel"),
              let fragmentFunction = library.makeFunction(name: "fragment_voxel") else {
            print("Failed to create shader library")
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float

        // Vertex descriptor for cube vertices
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
        descriptor.vertexDescriptor = vertexDescriptor

        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func setupGeometry() {
        // Simple cube vertices for each voxel
        let cubeVertices: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3( 1, -1, -1), SIMD3( 1,  1, -1), SIMD3(-1,  1, -1), // Back
            SIMD3(-1, -1,  1), SIMD3( 1, -1,  1), SIMD3( 1,  1,  1), SIMD3(-1,  1,  1)  // Front
        ]

        vertexBuffer = device.makeBuffer(bytes: cubeVertices, length: MemoryLayout<SIMD3<Float>>.stride * cubeVertices.count)

        // Cube indices
        let cubeIndices: [UInt16] = [
            0, 1, 2, 2, 3, 0,  // Back
            4, 5, 6, 6, 7, 4,  // Front
            0, 1, 5, 5, 4, 0,  // Bottom
            2, 3, 7, 7, 6, 2,  // Top
            0, 3, 7, 7, 4, 0,  // Left
            1, 2, 6, 6, 5, 1   // Right
        ]

        indexBuffer = device.makeBuffer(bytes: cubeIndices, length: MemoryLayout<UInt16>.stride * cubeIndices.count)

        // Uniform buffer for transformation matrices and params
        uniformBuffer = device.makeBuffer(length: 4096, options: .storageModeShared)
    }

    private func setupVoxelTexture() {
        // Create 3D texture from tensor data (side×side×side×4), tightly packed
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = side
        descriptor.height = side
        descriptor.depth = side
        descriptor.usage = [.shaderRead]

        voxelTexture = device.makeTexture(descriptor: descriptor)

        // Upload tensor data to texture
        voxelTexture?.replace(
            region: MTLRegionMake3D(0, 0, 0, side, side, side),
            mipmapLevel: 0,
            slice: 0,
            withBytes: tensorData.withUnsafeBytes { $0.baseAddress! },
            bytesPerRow: side * 4,
            bytesPerImage: side * side * 4
        )
    }

    func render(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer,
              let indexBuffer = indexBuffer,
              let uniformBuffer = uniformBuffer,
              let voxelTexture = voxelTexture else { return }

        // Create render pass descriptor with depth
        let descriptor = view.currentRenderPassDescriptor ?? MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store

        // Create depth texture if needed
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: drawable.texture.width,
            height: drawable.texture.height,
            mipmapped: false
        )
        depthDescriptor.usage = [.renderTarget]
        let depthTexture = device.makeTexture(descriptor: depthDescriptor)

        descriptor.depthAttachment.texture = depthTexture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.clearDepth = 1.0
        descriptor.depthAttachment.storeAction = .dontCare

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        // Update uniforms
        time += 0.016

        // Model matrix (rotation)
        let modelMatrix = matrix4x4_rotation(radians: rotation.x, axis: SIMD3(1, 0, 0)) *
                          matrix4x4_rotation(radians: rotation.y, axis: SIMD3(0, 1, 0)) *
                          matrix4x4_rotation(radians: rotation.z, axis: SIMD3(0, 0, 1))

        // View matrix (camera)
        let viewMatrix = matrix4x4_look_at(eye: SIMD3(0, 0, 5), center: SIMD3(0, 0, 0), up: SIMD3(0, 1, 0))

        // Projection matrix
        let aspect = Float(drawable.texture.width) / Float(drawable.texture.height)
        let projectionMatrix = matrix4x4_perspective(fovyRadians: Float.pi / 3, aspect: aspect, nearZ: 0.1, farZ: 100)

        // Pack uniforms
        struct UniformsCPU {
            var model: simd_float4x4
            var view: simd_float4x4
            var proj: simd_float4x4
            var time: Float
            var gridSize: UInt32
            var stride: UInt32
            var gridDiv: UInt32
            var alphaThreshold: Float
        }
        let gridDiv = UInt32(max(1, side / stridePerAxis))
        var uniforms = UniformsCPU(
            model: modelMatrix,
            view: viewMatrix,
            proj: projectionMatrix,
            time: time,
            gridSize: UInt32(side),
            stride: UInt32(stridePerAxis),
            gridDiv: gridDiv,
            alphaThreshold: 0.02 // be permissive; derive alpha from luma if needed
        )

        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<UniformsCPU>.size)

        // Draw voxels
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(voxelTexture, index: 0)
        encoder.setDepthStencilState(makeDepthStencilState())
        encoder.setCullMode(.back)

        // Draw instanced cubes for visible voxels (subsampled for performance)
        let voxelCount = Int(gridDiv * gridDiv * gridDiv)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 36,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: voxelCount
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeDepthStencilState() -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)
    }
}

// MARK: - Matrix Helper Functions

private func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let normalizedAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = normalizedAxis.x, y = normalizedAxis.y, z = normalizedAxis.z

    return simd_float4x4(columns: (
        SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
        SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

private func matrix4x4_look_at(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let z = normalize(eye - center)
    let x = normalize(cross(up, z))
    let y = cross(z, x)

    return simd_float4x4(columns: (
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    ))
}

private func matrix4x4_perspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
    let yScale = 1 / tanf(fovyRadians * 0.5)
    let xScale = yScale / aspect
    let zRange = farZ - nearZ
    let zScale = -(farZ + nearZ) / zRange
    let wzScale = -2 * farZ * nearZ / zRange

    return simd_float4x4(columns: (
        SIMD4<Float>(xScale, 0, 0, 0),
        SIMD4<Float>(0, yScale, 0, 0),
        SIMD4<Float>(0, 0, zScale, -1),
        SIMD4<Float>(0, 0, wzScale, 0)
    ))
}
