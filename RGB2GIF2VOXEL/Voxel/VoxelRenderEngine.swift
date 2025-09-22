// VoxelRenderEngine.swift
// Engine for managing voxel data and multi-view rendering

import Foundation
import Combine
import SceneKit
import ModelIO
import UniformTypeIdentifiers

// MARK: - Voxel Data Structure

struct VoxelData {
    let dimensions: (width: Int, height: Int, depth: Int)
    let indices: Data  // N×N×N indexed color data
    let palette: [UInt32]  // RGB palette

    var voxelCount: Int {
        dimensions.width * dimensions.height * dimensions.depth
    }

    // Create from CubeTensorData
    init(from tensor: CubeTensorData) {
        self.dimensions = (tensor.size, tensor.size, tensor.size)
        self.indices = Data(tensor.indices)
        self.palette = tensor.palette.map { UInt32($0) }
    }

    // For C FFI
    var cPointer: UnsafeMutableRawPointer {
        // Create a structure that can be passed to Rust
        let ptr = UnsafeMutablePointer<VoxelData>.allocate(capacity: 1)
        ptr.pointee = self
        return UnsafeMutableRawPointer(ptr)
    }
}

// MARK: - View Modes

enum VoxelViewMode: String, CaseIterable {
    case isometric = "Isometric"
    case orthographicFront = "Front"
    case orthographicTop = "Top"
    case orthographicSide = "Side"
    case perspective = "3D"
    case animated = "Animate"

    var systemImage: String {
        switch self {
        case .isometric: return "cube"
        case .orthographicFront: return "square"
        case .orthographicTop: return "square.stack"
        case .orthographicSide: return "rectangle"
        case .perspective: return "rotate.3d"
        case .animated: return "play.circle"
        }
    }
}

// MARK: - Render Engine

@MainActor
class VoxelRenderEngine: ObservableObject {

    // MARK: - Published Properties

    @Published var currentVoxelData: VoxelData?
    @Published var isLoading = false
    @Published var currentViewMode: VoxelViewMode = .isometric
    @Published var rotation = simd_float3(0, 0, 0)
    @Published var currentFrame = 0
    @Published var isAnimating = false

    // MARK: - Private Properties

    private var animationTimer: Timer?
    private let fileManager = FileManager.default

    // MARK: - Initialization

    init() {}

    deinit {
        animationTimer?.invalidate()
    }

    // MARK: - Data Loading

    func loadVoxelData(from tensor: CubeTensorData) {
        self.currentVoxelData = VoxelData(from: tensor)
    }

    func loadVoxelData(from url: URL) async throws {
        isLoading = true
        defer { isLoading = false }

        // For now, load as raw data
        // In future, use YXVReader to load compressed YXV files
        let data = try Data(contentsOf: url)

        // Parse based on file extension
        if url.pathExtension == "yxv" {
            // TODO: Implement YXV reading
            print("YXV reading not yet implemented")
        } else {
            // Assume raw voxel data
            // TODO: Parse dimensions and palette from metadata
        }
    }

    // MARK: - View Transformations

    func getTransformMatrix(for mode: VoxelViewMode) -> simd_float4x4 {
        switch mode {
        case .isometric:
            return getIsometricTransform()
        case .orthographicFront:
            return getOrthographicFrontTransform()
        case .orthographicTop:
            return getOrthographicTopTransform()
        case .orthographicSide:
            return getOrthographicSideTransform()
        case .perspective:
            return getPerspectiveTransform()
        case .animated:
            return simd_float4x4(diagonal: simd_float4(1, 1, 1, 1))
        }
    }

    private func getIsometricTransform() -> simd_float4x4 {
        // Classic isometric angles: 45° Y rotation, 35.264° X rotation
        let angleY = Float.pi / 4  // 45 degrees
        let angleX = Float(35.264 * .pi / 180)  // Magic angle for isometric

        // Future: Call Rust FFI
        // var transform = simd_float4x4()
        // voxel_get_isometric_transform(&transform)

        let rotY = simd_float4x4(rotationY: angleY)
        let rotX = simd_float4x4(rotationX: angleX)
        return rotX * rotY
    }

    private func getOrthographicFrontTransform() -> simd_float4x4 {
        return simd_float4x4(diagonal: simd_float4(1, 1, 1, 1))
    }

    private func getOrthographicTopTransform() -> simd_float4x4 {
        return simd_float4x4(rotationX: Float.pi / 2)
    }

    private func getOrthographicSideTransform() -> simd_float4x4 {
        return simd_float4x4(rotationY: Float.pi / 2)
    }

    private func getPerspectiveTransform() -> simd_float4x4 {
        let rotX = simd_float4x4(rotationX: rotation.x)
        let rotY = simd_float4x4(rotationY: rotation.y)
        let rotZ = simd_float4x4(rotationZ: rotation.z)
        return rotZ * rotY * rotX
    }

    // MARK: - Animation

    func startAnimation() {
        guard let voxelData = currentVoxelData else { return }

        isAnimating = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            self.currentFrame = (self.currentFrame + 1) % voxelData.dimensions.depth
        }
    }

    func stopAnimation() {
        isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func toggleAnimation() {
        if isAnimating {
            stopAnimation()
        } else {
            startAnimation()
        }
    }

    // MARK: - Slice Extraction

    func extractSlice(axis: Int, index: Int) -> Data? {
        guard let voxelData = currentVoxelData else { return nil }

        // Future: Call Rust FFI
        // var sliceData = Data(count: sliceSize)
        // sliceData.withUnsafeMutableBytes { buffer in
        //     voxel_extract_slice(voxelData.cPointer, Int32(axis), Int32(index), buffer.baseAddress)
        // }

        // For now, extract slice manually
        let (w, h, d) = voxelData.dimensions

        switch axis {
        case 0:  // YZ plane
            return extractYZSlice(at: index, from: voxelData)
        case 1:  // XZ plane
            return extractXZSlice(at: index, from: voxelData)
        case 2:  // XY plane (most common for frames)
            return extractXYSlice(at: index, from: voxelData)
        default:
            return nil
        }
    }

    private func extractXYSlice(at z: Int, from voxelData: VoxelData) -> Data {
        let (w, h, d) = voxelData.dimensions
        let sliceSize = w * h
        let offset = z * sliceSize
        return voxelData.indices.subdata(in: offset..<(offset + sliceSize))
    }

    private func extractXZSlice(at y: Int, from voxelData: VoxelData) -> Data {
        let (w, h, d) = voxelData.dimensions
        var slice = Data(capacity: w * d)

        for z in 0..<d {
            for x in 0..<w {
                let index = z * w * h + y * w + x
                slice.append(voxelData.indices[index])
            }
        }

        return slice
    }

    private func extractYZSlice(at x: Int, from voxelData: VoxelData) -> Data {
        let (w, h, d) = voxelData.dimensions
        var slice = Data(capacity: h * d)

        for z in 0..<d {
            for y in 0..<h {
                let index = z * w * h + y * w + x
                slice.append(voxelData.indices[index])
            }
        }

        return slice
    }

    // MARK: - Export Functions

    func exportUSDZ() async throws -> URL? {
        guard let voxelData = currentVoxelData else { return nil }

        print("Generating mesh from voxel data...")

        // Future: Call Rust to generate mesh
        // var vertices: UnsafeMutablePointer<Float>?
        // var vertexCount: Int32 = 0
        // var faces: UnsafeMutablePointer<Int32>?
        // var faceCount: Int32 = 0
        //
        // voxel_generate_mesh(
        //     voxelData.cPointer,
        //     0.1,  // Simplification level
        //     &vertices,
        //     &vertexCount,
        //     &faces,
        //     &faceCount
        // )

        // For now, create a simple cube mesh as placeholder
        let mesh = createPlaceholderMesh()

        // Create MDLAsset
        let asset = MDLAsset()
        asset.add(mesh)

        // Export to USDZ
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let usdzURL = documentsURL.appendingPathComponent("voxel_\(Date().timeIntervalSince1970).usdz")

        try asset.export(to: usdzURL)

        print("USDZ exported to: \(usdzURL.path)")
        return usdzURL
    }

    func exportReality() async throws -> URL? {
        // TODO: Implement Reality Composer export
        print("Reality export not yet implemented")
        return nil
    }

    func exportOBJ() async throws -> URL? {
        guard let voxelData = currentVoxelData else { return nil }

        // Generate OBJ format text
        var objContent = "# Voxel OBJ Export\n"
        objContent += "# Dimensions: \(voxelData.dimensions.width)×\(voxelData.dimensions.height)×\(voxelData.dimensions.depth)\n"
        objContent += "\n"

        // TODO: Generate actual vertices and faces
        // For now, export a simple cube
        objContent += """
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        v 0 0 1
        v 1 0 1
        v 1 1 1
        v 0 1 1

        f 1 2 3 4
        f 5 8 7 6
        f 1 5 6 2
        f 2 6 7 3
        f 3 7 8 4
        f 4 8 5 1
        """

        // Save to file
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let objURL = documentsURL.appendingPathComponent("voxel_\(Date().timeIntervalSince1970).obj")

        try objContent.write(to: objURL, atomically: true, encoding: .utf8)

        print("OBJ exported to: \(objURL.path)")
        return objURL
    }

    // MARK: - Helper Functions

    private func createPlaceholderMesh() -> MDLMesh {
        // Create a simple cube mesh as placeholder
        let allocator = MDLMeshBufferDataAllocator()
        let mesh = MDLMesh(boxWithExtent: vector3(1, 1, 1),
                          segments: vector3(1, 1, 1),
                          inwardNormals: false,
                          geometryType: .triangles,
                          allocator: allocator)
        mesh.name = "VoxelMesh"
        return mesh
    }
}

// MARK: - Matrix Extensions

extension simd_float4x4 {
    init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, c, -s, 0),
            simd_float4(0, s, c, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(
            simd_float4(c, 0, s, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(-s, 0, c, 0),
            simd_float4(0, 0, 0, 1)
        )
    }

    init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(
            simd_float4(c, -s, 0, 0),
            simd_float4(s, c, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
    }
}