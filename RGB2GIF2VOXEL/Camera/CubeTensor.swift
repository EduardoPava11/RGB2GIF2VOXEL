import Foundation
import CryptoKit

/// Represents an N×N×N cube tensor of quantized frames
public struct CubeTensor {
    /// The captured and quantized frames (z-major: frame 0..N-1)
    public let frames: [QuantizedFrame]

    /// Side dimension (N)
    public let sideN: Int

    /// Palette size used for quantization
    public let paletteSize: Int

    /// Initialize with frames and metadata
    public init(frames: [QuantizedFrame], sideN: Int, paletteSize: Int) {
        self.frames = frames
        self.sideN = sideN
        self.paletteSize = paletteSize
    }

    /// Total voxel count (N³)
    public var voxelCount: Int {
        return sideN * sideN * sideN
    }

    /// Build a flat array of all RGBA data (N³ × 4 bytes), z-major order
    public func flatIndices() -> Data {
        var data = Data(capacity: voxelCount * 4)
        for frame in frames {
            data.append(frame.data)
        }
        return data
    }

    /// Global palette - not available in new API, return empty
    public var globalPalette: [UInt32] {
        // Note: New API doesn't expose palette separately
        return []
    }

    /// Export for GPU 3D texture
    public func export3DTexture() -> (indices: Data, palette: Data) {
        let indices = flatIndices()
        var paletteData = Data(capacity: globalPalette.count * 4)
        for color in globalPalette {
            let r = UInt8((color >> 16) & 0xFF)
            let g = UInt8((color >> 8) & 0xFF)
            let b = UInt8(color & 0xFF)
            let a = UInt8(255)
            paletteData.append(r)
            paletteData.append(g)
            paletteData.append(b)
            paletteData.append(a)
        }
        return (indices, paletteData)
    }

    /// Deterministic hash of tensor contents
    public func deterministicHash() -> String {
        var hasher = StableHasher()
        hasher.update(sideN)
        hasher.update(paletteSize)
        for frame in frames {
            // Hash the RGBA data directly
            hasher.update(frame.data)
        }
        return hasher.finalize()
    }

    /// Convert to CubeTensorData for GIF encoding/export
    public func toCubeTensorData() -> CubeTensorData {
        let indicesData = flatIndices()
        return CubeTensorData(
            size: sideN,
            indices: [UInt8](indicesData),
            palette: globalPalette,
            paletteSize: paletteSize
        )
    }
}

/// Simple stable hasher for deterministic hashing
struct StableHasher {
    private var data = Data()

    mutating func update(_ value: Int) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    mutating func update(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    mutating func update(_ bytes: Data) {
        data.append(bytes)
    }

    func finalize() -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
