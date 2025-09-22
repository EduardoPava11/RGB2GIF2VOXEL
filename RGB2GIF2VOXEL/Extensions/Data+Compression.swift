//
//  Data+Compression.swift
//  RGB2GIF2VOXEL
//
//  Compression utilities using Apple's Compression framework
//

import Foundation
import Compression

// MARK: - Compression Algorithm Type

public enum CompressionAlgorithm {
    case lzfse
    case lz4
    case lzma
    case zlib
}

// MARK: - Compression Algorithm Extension

extension CompressionAlgorithm {
    var algorithm: compression_algorithm {
        switch self {
        case .lzfse:
            return COMPRESSION_LZFSE
        case .lz4:
            return COMPRESSION_LZ4
        case .lzma:
            return COMPRESSION_LZMA
        case .zlib:
            return COMPRESSION_ZLIB
        }
    }
}

// MARK: - Data Compression Extension

extension Data {

    /// Compresses the data using the specified algorithm
    /// - Parameter algorithm: The compression algorithm to use
    /// - Returns: Compressed data
    /// - Throws: Error if compression fails
    func compressed(using algorithm: CompressionAlgorithm) throws -> Data {
        return try perform(operation: .compression, algorithm: algorithm)
    }

    /// Decompresses the data using the specified algorithm
    /// - Parameter algorithm: The compression algorithm that was used to compress
    /// - Returns: Decompressed data
    /// - Throws: Error if decompression fails
    func decompressed(using algorithm: CompressionAlgorithm) throws -> Data {
        return try perform(operation: .decompression, algorithm: algorithm)
    }

    // MARK: - Private Implementation

    private enum CompressionOperation {
        case compression
        case decompression

        var operation: compression_stream_operation {
            switch self {
            case .compression:
                return COMPRESSION_STREAM_ENCODE
            case .decompression:
                return COMPRESSION_STREAM_DECODE
            }
        }

        var flags: Int32 {
            switch self {
            case .compression:
                return Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            case .decompression:
                return 0
            }
        }
    }

    private enum CompressionError: LocalizedError {
        case initializationFailed
        case compressionFailed
        case decompressionFailed
        case invalidData

        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Failed to initialize compression stream"
            case .compressionFailed:
                return "Compression operation failed"
            case .decompressionFailed:
                return "Decompression operation failed"
            case .invalidData:
                return "Invalid or corrupted data"
            }
        }
    }

    private func perform(operation: CompressionOperation, algorithm: CompressionAlgorithm) throws -> Data {
        guard !self.isEmpty else { return Data() }

        // Create dummy buffers for initialization
        var dummyDst: UInt8 = 0
        var dummySrc: UInt8 = 0

        var stream = compression_stream(
            dst_ptr: &dummyDst,
            dst_size: 0,
            src_ptr: &dummySrc,
            src_size: 0,
            state: nil
        )

        var status = compression_stream_init(
            &stream,
            operation.operation,
            algorithm.algorithm
        )

        guard status == COMPRESSION_STATUS_OK else {
            throw CompressionError.initializationFailed
        }

        defer {
            compression_stream_destroy(&stream)
        }

        let bufferSize = 65536 // 64KB buffer
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        var outputData = Data()

        self.withUnsafeBytes { inputBytes in
            guard let inputBaseAddress = inputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            stream.src_ptr = inputBaseAddress
            stream.src_size = self.count

            repeat {
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize

                status = compression_stream_process(&stream, operation.flags)

                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let bytesWritten = bufferSize - stream.dst_size
                    if bytesWritten > 0 {
                        outputData.append(buffer, count: bytesWritten)
                    }

                case COMPRESSION_STATUS_ERROR:
                    break

                default:
                    break
                }

            } while status == COMPRESSION_STATUS_OK
        }

        guard status == COMPRESSION_STATUS_END else {
            throw operation == .compression ?
                CompressionError.compressionFailed :
                CompressionError.decompressionFailed
        }

        return outputData
    }
}

// MARK: - Convenience Methods

extension Data {

    /// Quick LZFSE compression (Apple's algorithm, best for most cases)
    func compressedLZFSE() throws -> Data {
        return try compressed(using: .lzfse)
    }

    /// Quick LZFSE decompression
    func decompressedLZFSE() throws -> Data {
        return try decompressed(using: .lzfse)
    }

    /// Quick LZ4 compression (fastest, less compression)
    func compressedLZ4() throws -> Data {
        return try compressed(using: .lz4)
    }

    /// Quick LZ4 decompression
    func decompressedLZ4() throws -> Data {
        return try decompressed(using: .lz4)
    }

    /// Returns compression ratio (original size / compressed size)
    func compressionRatio(using algorithm: CompressionAlgorithm) -> Double? {
        guard let compressed = try? compressed(using: algorithm),
              compressed.count > 0 else { return nil }
        return Double(self.count) / Double(compressed.count)
    }

    /// Returns the best algorithm for this data based on compression ratio
    func bestCompressionAlgorithm() -> (algorithm: CompressionAlgorithm, ratio: Double)? {
        let algorithms: [CompressionAlgorithm] = [.lzfse, .lz4, .zlib, .lzma]

        var best: (CompressionAlgorithm, Double)?

        for algorithm in algorithms {
            if let ratio = compressionRatio(using: algorithm) {
                if best == nil || ratio > best!.1 {
                    best = (algorithm, ratio)
                }
            }
        }

        return best.map { (algorithm: $0.0, ratio: $0.1) }
    }
}