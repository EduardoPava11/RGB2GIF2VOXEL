//
//  YinGifProcessor.swift
//  RGB2GIF2VOXEL
//
//  Swift-only processor for frame processing (fallback to avoid Rust dependency)
//

import Foundation
import Accelerate

/// Pure-Swift frame processor that downsizes BGRA frames to targetSize.
/// This is a fidelity-preserving fallback; quantization/palette control is left to ImageIO or higher-level logic.
public class YinGifProcessor {

    public init() {}

    /// Process a BGRA frame to a resized RGBA buffer (no quantization).
    public func processFrame(
        bgraData: Data,
        width: Int,
        height: Int,
        targetSize: Int,
        paletteSize: Int,
        frameIndex: Int = 0
    ) throws -> QuantizedFrame {
        // Quick path: if already the right size, return as-is
        if width == targetSize, height == targetSize {
            return QuantizedFrame(index: frameIndex, data: bgraData, width: targetSize, height: targetSize)
        }

        let srcBytesPerRow = width * 4
        let destBytesPerRow = targetSize * 4

        return try bgraData.withUnsafeBytes { srcPtr -> QuantizedFrame in
            guard let srcBase = srcPtr.baseAddress else {
                throw YinGifProcessingError.invalidInput
            }

            let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: targetSize * targetSize * 4)
            defer { destData.deallocate() }

            var srcBuffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: srcBase),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: srcBytesPerRow
            )

            var destBuffer = vImage_Buffer(
                data: destData,
                height: vImagePixelCount(targetSize),
                width: vImagePixelCount(targetSize),
                rowBytes: destBytesPerRow
            )

            // Scale 4×8-bit channels (ARGB routine works channel-agnostically)
            let err = vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
            guard err == kvImageNoError else {
                throw YinGifProcessingError.processingFailed("vImage scaling failed: \(err)")
            }

            let resized = Data(bytes: destData, count: targetSize * targetSize * 4)

            return QuantizedFrame(
                index: frameIndex,
                data: resized,
                width: targetSize,
                height: targetSize
            )
        }
    }

    /// Async helper
    public func processFrameAsync(
        bgraData: Data,
        width: Int,
        height: Int,
        targetSize: Int,
        paletteSize: Int
    ) async throws -> QuantizedFrame {
        return try await Task.detached(priority: .userInitiated) {
            try self.processFrame(
                bgraData: bgraData,
                width: width,
                height: height,
                targetSize: targetSize,
                paletteSize: paletteSize
            )
        }.value
    }
}

// Minimal ProcessingError used here to avoid Rust dependency.
// Using internal scope to avoid conflicts with Core/Errors.swift
internal enum YinGifProcessingError: LocalizedError {
    case invalidInput
    case processingFailed(String)
    case ffiError(code: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Invalid input"
        case .processingFailed(let msg): return msg
        case .ffiError(let code): return "FFI error: \(code)"
        }
    }
}
