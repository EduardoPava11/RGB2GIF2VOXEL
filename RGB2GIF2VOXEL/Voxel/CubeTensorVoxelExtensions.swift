// CubeTensorVoxelExtensions.swift
// Extensions to integrate CubeTensor with various voxel rendering approaches

import Foundation
import ModelIO
import SceneKit
import Metal

// MARK: - Voxel Integration Extensions

extension CubeTensor {

    // MARK: - SceneKit Integration (Current Approach)

    /// Generate SceneKit geometry from tensor with sparse sampling for performance
    /// Each frame becomes a Z-slice, colored by palette
    /// For 256³ cubes, uses sparse sampling (every 32nd voxel) for performance
    func toSCNGeometry() -> SCNGeometry {
        let voxelSize: Float = 0.1
        let spacing: Float = 0.01
        
        // Adaptive sparse sampling based on cube size
        // For N=128, render every voxel as requested
        let sparseStep: Int
        if sideN >= 256 {
            sparseStep = 32
        } else if sideN == 128 {
            sparseStep = 1
        } else {
            sparseStep = 1
        }
        let actualVoxelSize = voxelSize * Float(sparseStep)
        
        print("🔵 Rendering \(sideN)³ voxel cube with sparse step: \(sparseStep)")

        // Create geometry source for vertices
        var vertices: [SCNVector3] = []
        var colors: [Float] = []
        var indices: [Int32] = []

        var vertexIndex: Int32 = 0

        for (z, frame) in frames.enumerated() {
            // Skip frames for sparse sampling
            if z % sparseStep != 0 { continue }
            
            for y in stride(from: 0, to: sideN, by: sparseStep) {
                for x in stride(from: 0, to: sideN, by: sparseStep) {
                    let pixelIndex = y * sideN + x
                    let rgbaIndex = pixelIndex * 4
                    guard rgbaIndex + 3 < frame.data.count else { continue }

                    // Extract RGBA from data
                    let r = Float(frame.data[rgbaIndex]) / 255.0
                    let g = Float(frame.data[rgbaIndex + 1]) / 255.0
                    let b = Float(frame.data[rgbaIndex + 2]) / 255.0
                    let a = Float(frame.data[rgbaIndex + 3]) / 255.0

                    // Skip transparent voxels
                    if a < 0.01 { continue }

                    // Create cube vertices (8 per voxel) - scaled for sparse sampling
                    let basePos = SCNVector3(
                        Float(x) * (actualVoxelSize + spacing),
                        Float(y) * (actualVoxelSize + spacing),
                        Float(z) * (actualVoxelSize + spacing)
                    )

                    // Add 8 vertices for this voxel
                    for i in 0..<8 {
                        let vx = basePos.x + (i & 1 == 0 ? 0 : actualVoxelSize)
                        let vy = basePos.y + (i & 2 == 0 ? 0 : actualVoxelSize)
                        let vz = basePos.z + (i & 4 == 0 ? 0 : actualVoxelSize)
                        vertices.append(SCNVector3(vx, vy, vz))
                        colors.append(contentsOf: [r, g, b, 1.0])
                    }

                    // Add cube face indices (12 triangles, 36 indices)
                    let cubeIndices: [Int32] = [
                        // Front face
                        0,1,2, 1,3,2,
                        // Back face
                        4,6,5, 5,6,7,
                        // Top face
                        2,3,6, 3,7,6,
                        // Bottom face
                        0,4,1, 1,4,5,
                        // Right face
                        1,5,3, 3,5,7,
                        // Left face
                        0,2,4, 2,6,4
                    ]

                    for idx in cubeIndices {
                        indices.append(vertexIndex + idx)
                    }
                    vertexIndex += 8
                }
            }
        }

        // Create geometry sources
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let colorSource = SCNGeometrySource(data: Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size),
                                           semantic: .color,
                                           vectorCount: vertices.count,
                                           usesFloatComponents: true,
                                           componentsPerVector: 4,
                                           bytesPerComponent: MemoryLayout<Float>.size,
                                           dataOffset: 0,
                                           dataStride: MemoryLayout<Float>.size * 4)

        // Create geometry element
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        // Create geometry
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])

        return geometry
    }

    // MARK: - MDLVoxelArray Integration (For Export)

    /// Convert to MDLVoxelArray for mesh generation and export
    func toMDLVoxelArray(divisions: Int32 = 1) -> MDLVoxelArray {
        let extent = MDLAxisAlignedBoundingBox(
            maxBounds: vector_float3(Float(sideN), Float(sideN), Float(sideN)),
            minBounds: vector_float3(0, 0, 0)
        )

        let voxelArray = MDLVoxelArray(data: Data(), boundingBox: extent, voxelExtent: 1.0 / Float(divisions))

        // Convert each frame to Z-slice
        for (z, frame) in frames.enumerated() {
            for y in 0..<sideN {
                for x in 0..<sideN {
                    let idx = y * sideN + x
                    let rgbaIndex = idx * 4
                    guard rgbaIndex + 3 < frame.data.count else { continue }

                    // Check alpha channel for transparency
                    let alpha = frame.data[rgbaIndex + 3]

                    // Set voxel if non-transparent
                    if alpha > 0 {
                        let voxelIndex = MDLVoxelIndex(arrayLiteral: Int32(x), Int32(y), Int32(z))
                        voxelArray.setVoxelAtIndex(voxelIndex)
                    }
                }
            }
        }

        return voxelArray
    }

    // MARK: - Metal 3D Texture (For GPU Rendering)

    /// Pack tensor into Metal 3D texture for GPU ray marching
    func toMetal3DTexture(device: MTLDevice) -> (texture: MTLTexture, palette: MTLTexture)? {
        // Create 3D texture for palette indices
        let indexDescriptor = MTLTextureDescriptor()
        indexDescriptor.textureType = .type3D
        indexDescriptor.pixelFormat = .r8Uint  // Single channel for palette index
        indexDescriptor.width = sideN
        indexDescriptor.height = sideN
        indexDescriptor.depth = sideN
        indexDescriptor.usage = [.shaderRead]

        guard let indexTexture = device.makeTexture(descriptor: indexDescriptor) else {
            return nil
        }

        // Pack all frame RGBA data into 3D texture
        // Note: We'll treat this as a single-channel intensity for now
        var voxelIndices = [UInt8]()
        for frame in frames {
            // Extract intensity from RGBA data (using red channel as representative)
            for i in stride(from: 0, to: frame.data.count, by: 4) {
                voxelIndices.append(frame.data[i]) // Use red channel as index
            }
        }

        indexTexture.replace(
            region: MTLRegionMake3D(0, 0, 0, sideN, sideN, sideN),
            mipmapLevel: 0,
            slice: 0,
            withBytes: voxelIndices,
            bytesPerRow: sideN,
            bytesPerImage: sideN * sideN
        )

        // Create 1D texture for color palette
        let paletteDescriptor = MTLTextureDescriptor()
        paletteDescriptor.textureType = .type1D
        paletteDescriptor.pixelFormat = .rgba8Unorm
        paletteDescriptor.width = paletteSize
        paletteDescriptor.usage = [.shaderRead]

        guard let paletteTexture = device.makeTexture(descriptor: paletteDescriptor) else {
            return nil
        }

        // Create a grayscale palette since we don't have palette data anymore
        // Generate a gradient from black to white
        var paletteColors = [UInt8]()
        for i in 0..<paletteSize {
            let intensity = UInt8((i * 255) / (paletteSize - 1))
            paletteColors.append(intensity) // R
            paletteColors.append(intensity) // G
            paletteColors.append(intensity) // B
            paletteColors.append(255)        // A
        }

        paletteTexture.replace(
            region: MTLRegionMake1D(0, paletteSize),
            mipmapLevel: 0,
            slice: 0,
            withBytes: paletteColors,
            bytesPerRow: 0,
            bytesPerImage: 0
        )

        return (indexTexture, paletteTexture)
    }

    // MARK: - View Mode Transforms

    /// Get transform matrix for different view modes
    func getViewTransform(for mode: VoxelViewMode, frame: Int = 0) -> simd_float4x4 {
        switch mode {
        case .orthographicFront:
            return matrix_identity_float4x4

        case .orthographicSide:
            // Rotate 90° around Y to show side view
            return simd_float4x4(simd_quatf(angle: .pi/2, axis: simd_float3(0, 1, 0)))

        case .orthographicTop:
            // Rotate 90° around X to show top view
            return simd_float4x4(simd_quatf(angle: .pi/2, axis: simd_float3(1, 0, 0)))

        case .perspective:
            // Full 3D perspective
            let rotX = simd_quatf(angle: .pi/8, axis: simd_float3(1, 0, 0))
            let rotY = simd_quatf(angle: .pi/3, axis: simd_float3(0, 1, 0))
            return simd_float4x4(rotX * rotY)

        case .isometric:
            // Isometric-style rotation
            let rotX = simd_quatf(angle: .pi/6, axis: simd_float3(1, 0, 0))
            let rotY = simd_quatf(angle: .pi/4, axis: simd_float3(0, 1, 0))
            return simd_float4x4(rotX * rotY)

        case .animated:
            // Identity with frame-based Z offset for slicing
            var transform = matrix_identity_float4x4
            transform[3][2] = Float(frame - sideN/2) * 0.1
            return transform
        }
    }

    // MARK: - Export Helpers

    /// Generate voxel mesh for export
    func generateVoxelMesh() -> MDLMesh? {
        let voxelArray = toMDLVoxelArray()

        // Generate mesh from voxel array
        let mesh = voxelArray.mesh(using: MDLMeshBufferDataAllocator())
        mesh?.name = "CubeTensor_\(sideN)x\(sideN)x\(sideN)"

        return mesh
    }
}

// MARK: - Helper Extensions

extension simd_float4x4 {
    init(_ quaternion: simd_quatf) {
        self = matrix_float4x4(quaternion)
    }
}
