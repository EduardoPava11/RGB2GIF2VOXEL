// YXV (YinVoxel) Types and Constants
// Manual definitions for chunk records and constants

import Foundation

// MARK: - Constants

enum YXVConstants {
    static let magic: [UInt8] = [0x59, 0x58, 0x56, 0x00] // "YXV\0"
    static let currentVersion: UInt32 = 1
    static let chunkAlignment: Int = 64 // Align chunks to 64 bytes for better I/O
}

// MARK: - Chunk Types

enum YXVChunkType: UInt8 {
    case palette = 0
    case frame = 1
    case metadata = 2
    case thumbnail = 3
}

// MARK: - Compression Types

enum YXVCompressionType: UInt8 {
    case none = 0
    case lz4 = 1
    case lzfse = 2
    case zstd = 3

    var algorithm: CompressionAlgorithm? {
        switch self {
        case .none: return nil
        case .lz4: return .lz4
        case .lzfse: return .lzfse
        case .zstd: return .lzma  // Using LZMA as zstd alternative
        }
    }
}

// MARK: - Color Modes

enum YXVColorMode: UInt8 {
    case indexed = 0  // 1 byte per voxel
    case rgb24 = 1    // 3 bytes per voxel (future)
    case rgba32 = 2   // 4 bytes per voxel (future)

    var bytesPerVoxel: Int {
        switch self {
        case .indexed: return 1
        case .rgb24: return 3
        case .rgba32: return 4
        }
    }
}

// MARK: - View Types

enum YXVViewType: UInt8 {
    case isometric = 0
    case orthographicFront = 1
    case orthographicTop = 2
    case orthographicSide = 3
    case perspective = 4
    case animated = 5
}

// MARK: - Fixed-Size Structures

// ChunkRecord: 24 bytes (matches FlatBuffers struct)
struct YXVChunkRecord {
    let type: YXVChunkType
    let offset: UInt64
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let checksum: UInt32

    // Memberwise initializer
    init(type: YXVChunkType, offset: UInt64, compressedSize: UInt32, uncompressedSize: UInt32, checksum: UInt32) {
        self.type = type
        self.offset = offset
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.checksum = checksum
    }

    // Serialize to Data
    var data: Data {
        var data = Data(capacity: 24)
        data.append(type.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: checksum.littleEndian) { Array($0) })
        // Pad to 24 bytes
        while data.count < 24 {
            data.append(0)
        }
        return data
    }

    // Deserialize from Data
    init?(data: Data) {
        guard data.count >= 24 else { return nil }

        guard let typeRaw = YXVChunkType(rawValue: data[0]) else { return nil }
        self.type = typeRaw

        self.offset = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: 1, as: UInt64.self).littleEndian
        }

        self.compressedSize = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: 9, as: UInt32.self).littleEndian
        }

        self.uncompressedSize = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: 13, as: UInt32.self).littleEndian
        }

        self.checksum = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: 17, as: UInt32.self).littleEndian
        }
    }
}

// MARK: - Container Structure

struct YXVContainer {
    let header: Data  // FlatBuffers header
    let chunks: [YXVChunkRecord]
    let payloads: [Data]  // Compressed chunk payloads
}

// MARK: - Error Types

enum YXVError: LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt32)
    case compressionFailed
    case decompressionFailed
    case checksumMismatch
    case invalidChunkRecord
    case fileNotFound
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Invalid YXV file magic number"
        case .unsupportedVersion(let version):
            return "Unsupported YXV version: \(version)"
        case .compressionFailed:
            return "Failed to compress data"
        case .decompressionFailed:
            return "Failed to decompress data"
        case .checksumMismatch:
            return "Chunk checksum verification failed"
        case .invalidChunkRecord:
            return "Invalid chunk record structure"
        case .fileNotFound:
            return "YXV file not found"
        case .writeFailed:
            return "Failed to write YXV file"
        }
    }
}