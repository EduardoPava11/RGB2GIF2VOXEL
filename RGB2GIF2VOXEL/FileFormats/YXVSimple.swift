//
//  YXVSimple.swift
//  RGB2GIF2VOXEL
//
//  Simplified YXV I/O for CubeTensor storage
//

import Foundation
import Compression
import CryptoKit

/// Simplified YXV Writer for CubeTensor
public class YXVWriter {

    public init() {}

    /// Write a CubeTensor to YXV format
    public func write(_ tensor: CubeTensor, to url: URL) throws {
        // Create container data
        var containerData = Data()

        // Add magic number
        containerData.append(Data(YXVConstants.magic))

        // Add version
        var version = YXVConstants.currentVersion.littleEndian
        containerData.append(Data(bytes: &version, count: 4))

        // Add metadata
        var dimensions = UInt16(tensor.sideN).littleEndian
        containerData.append(Data(bytes: &dimensions, count: 2))
        containerData.append(Data(bytes: &dimensions, count: 2))
        containerData.append(Data(bytes: &dimensions, count: 2))

        var paletteSize = UInt16(tensor.paletteSize).littleEndian
        containerData.append(Data(bytes: &paletteSize, count: 2))

        // Add compression type (using lzfse)
        containerData.append(YXVCompressionType.lzfse.rawValue)

        // Get tensor data
        let (indices, palette) = tensor.export3DTexture()

        // Compress indices
        guard let compressedIndices = try? compress(data: indices, algorithm: .lzfse) else {
            throw YXVError.compressionFailed
        }

        // Compress palette
        guard let compressedPalette = try? compress(data: palette, algorithm: .lzfse) else {
            throw YXVError.compressionFailed
        }

        // Add chunk records
        var currentOffset = UInt64(containerData.count + 48) // Header + 2 chunk records

        // Palette chunk record
        let paletteChunk = YXVChunkRecord(
            type: .palette,
            offset: currentOffset,
            compressedSize: UInt32(compressedPalette.count),
            uncompressedSize: UInt32(palette.count),
            checksum: calculateChecksum(compressedPalette)
        )
        containerData.append(paletteChunk.data)
        currentOffset += UInt64(compressedPalette.count)

        // Frame chunk record (indices)
        let frameChunk = YXVChunkRecord(
            type: .frame,
            offset: currentOffset,
            compressedSize: UInt32(compressedIndices.count),
            uncompressedSize: UInt32(indices.count),
            checksum: calculateChecksum(compressedIndices)
        )
        containerData.append(frameChunk.data)

        // Add payloads
        containerData.append(compressedPalette)
        containerData.append(compressedIndices)

        // Write to file
        try containerData.write(to: url)
    }

    private func compress(data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        guard let compressed = data.compressed(using: algorithm) else {
            throw YXVError.compressionFailed
        }
        return compressed
    }

    private func calculateChecksum(_ data: Data) -> UInt32 {
        let hash = SHA256.hash(data: data)
        var checksum: UInt32 = 0
        var index = 0
        for byte in hash.prefix(4) {
            checksum |= UInt32(byte) << (index * 8)
            index += 1
        }
        return checksum
    }
}

/// Simplified YXV Reader for CubeTensor
public class YXVReader {

    public init() {}

    /// Read a CubeTensor from YXV format
    public func read(from url: URL) throws -> CubeTensor {
        guard let data = try? Data(contentsOf: url) else {
            throw YXVError.fileNotFound
        }

        var offset = 0

        // Verify magic
        let magic = data.subdata(in: offset..<offset+4)
        guard magic == Data(YXVConstants.magic) else {
            throw YXVError.invalidMagic
        }
        offset += 4

        // Read version
        let version = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
        guard version == YXVConstants.currentVersion else {
            throw YXVError.unsupportedVersion(version)
        }
        offset += 4

        // Read dimensions
        let width = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
        offset += 2
        let height = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
        offset += 2
        let depth = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
        offset += 2

        // Read palette size
        let paletteSize = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
        offset += 2

        // Read compression type
        let compressionType = data[offset]
        guard let compression = YXVCompressionType(rawValue: compressionType) else {
            throw YXVError.decompressionFailed
        }
        offset += 1

        // Read chunk records
        let paletteChunkData = data.subdata(in: offset..<offset+24)
        guard let paletteChunk = YXVChunkRecord(data: paletteChunkData) else {
            throw YXVError.invalidChunkRecord
        }
        offset += 24

        let frameChunkData = data.subdata(in: offset..<offset+24)
        guard let frameChunk = YXVChunkRecord(data: frameChunkData) else {
            throw YXVError.invalidChunkRecord
        }
        offset += 24

        // Read and decompress palette
        let compressedPalette = data.subdata(
            in: Int(paletteChunk.offset)..<Int(paletteChunk.offset + UInt64(paletteChunk.compressedSize))
        )
        guard let paletteData = decompress(
            data: compressedPalette,
            algorithm: compression.algorithm ?? .lzfse
        ) else {
            throw YXVError.decompressionFailed
        }

        // Read and decompress indices
        let compressedIndices = data.subdata(
            in: Int(frameChunk.offset)..<Int(frameChunk.offset + UInt64(frameChunk.compressedSize))
        )
        guard let indicesData = decompress(
            data: compressedIndices,
            algorithm: compression.algorithm ?? .lzfse
        ) else {
            throw YXVError.decompressionFailed
        }

        // Convert palette data to UInt32 array
        var palette: [UInt32] = []
        for i in stride(from: 0, to: paletteData.count, by: 4) {
            let r = UInt32(paletteData[i])
            let g = UInt32(paletteData[i+1])
            let b = UInt32(paletteData[i+2])
            let color = (r << 16) | (g << 8) | b
            palette.append(color)
        }

        // Create frames from indices (split into N frames)
        let frameSize = Int(width) * Int(height)
        var frames: [QuantizedFrame] = []

        for frameIdx in 0..<Int(depth) {
            let startIdx = frameIdx * frameSize
            let endIdx = min(startIdx + frameSize, indicesData.count)
            let frameIndices = indicesData.subdata(in: startIdx..<endIdx)

            // Convert indices and palette to RGBA data for new API
            var rgbaData = Data(capacity: frameSize * 4)
            for byte in frameIndices {
                let colorIndex = Int(byte) % palette.count
                let color = palette[colorIndex]
                rgbaData.append(UInt8((color >> 16) & 0xFF)) // R
                rgbaData.append(UInt8((color >> 8) & 0xFF))  // G
                rgbaData.append(UInt8(color & 0xFF))         // B
                rgbaData.append(0xFF)                        // A
            }

            let frame = QuantizedFrame(
                index: frameIdx,
                data: rgbaData,
                width: Int(width),
                height: Int(height)
            )
            frames.append(frame)
        }

        return CubeTensor(
            frames: frames,
            sideN: Int(width),
            paletteSize: Int(paletteSize)
        )
    }

    private func decompress(data: Data, algorithm: CompressionAlgorithm) -> Data? {
        return data.decompressed(using: algorithm)
    }
}

// MARK: - Data Compression Extensions

private extension Data {
    func compressed(using algorithm: CompressionAlgorithm) -> Data? {
        return self.withUnsafeBytes { sourceBuffer in
            let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress!
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { destinationBuffer.deallocate() }

            let compressedSize = compression_encode_buffer(
                destinationBuffer, count,
                sourcePtr, count,
                nil, algorithm.rawValue
            )

            guard compressedSize > 0 else { return nil }
            return Data(bytes: destinationBuffer, count: compressedSize)
        }
    }

    func decompressed(using algorithm: CompressionAlgorithm) -> Data? {
        return self.withUnsafeBytes { sourceBuffer in
            let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress!
            let destinationBufferSize = count * 4 // Assume 4x expansion max
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
            defer { destinationBuffer.deallocate() }

            let decompressedSize = compression_decode_buffer(
                destinationBuffer, destinationBufferSize,
                sourcePtr, count,
                nil, algorithm.rawValue
            )

            guard decompressedSize > 0 else { return nil }
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
    }
}

// MARK: - Compression Algorithm Extension

private extension CompressionAlgorithm {
    var rawValue: compression_algorithm {
        switch self {
        case .lz4: return COMPRESSION_LZ4
        case .lzfse: return COMPRESSION_LZFSE
        case .lzma: return COMPRESSION_LZMA
        case .zlib: return COMPRESSION_ZLIB
        default: return COMPRESSION_LZFSE
        }
    }
}