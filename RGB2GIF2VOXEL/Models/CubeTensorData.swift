import Foundation

/// Canonical data structure for N×N×N cube tensor used in GIF encoding
/// This is the single source of truth for cube tensor data representation
public struct CubeTensorData {
    /// Side dimension (N for N×N×N cube)
    public let size: Int

    /// Flattened color indices for all voxels (N³ elements)
    public let indices: [UInt8]

    /// Color palette (up to 256 colors)
    public let palette: [UInt32]

    /// Actual palette size used (≤256)
    public let paletteSize: Int

    /// Optional raw RGBA tensor data from Rust (256×256×256×4 bytes)
    /// This is the full-resolution voxel data for 3D visualization
    public let rawTensorData: Data?

    public init(size: Int, indices: [UInt8], palette: [UInt32], paletteSize: Int, rawTensorData: Data? = nil) {
        self.size = size
        self.indices = indices
        self.palette = palette
        self.paletteSize = paletteSize
        self.rawTensorData = rawTensorData
    }

    /// Total voxel count in the cube
    public var voxelCount: Int {
        return size * size * size
    }
}