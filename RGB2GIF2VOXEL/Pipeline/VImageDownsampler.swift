//
//  VImageDownsampler.swift
//  RGB2GIF2VOXEL
//
//  High-performance image downsampling using vImage framework
//  Replaces UIKit-based downsizing for better performance
//

import Foundation
import Accelerate
import CoreGraphics

/// High-performance image downsampler using vImage
public struct VImageDownsampler {

    /// Downsample BGRA data using vImage Lanczos algorithm
    /// - Parameters:
    ///   - bgraData: Input BGRA data
    ///   - fromSize: Source width/height (assumes square)
    ///   - toSize: Target width/height (assumes square)
    /// - Returns: Downsampled BGRA data
    public static func downsample(
        _ bgraData: Data,
        from fromSize: Int,
        to toSize: Int
    ) throws -> Data {

        // Validate input
        guard bgraData.count == fromSize * fromSize * 4 else {
            throw DownsampleError.invalidDataSize(expected: fromSize * fromSize * 4, actual: bgraData.count)
        }

        // Prepare source buffer (must be var for inout parameter)
        var sourceBuffer = bgraData.withUnsafeBytes { bytes -> vImage_Buffer in
            vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                height: vImagePixelCount(fromSize),
                width: vImagePixelCount(fromSize),
                rowBytes: fromSize * 4
            )
        }

        // Allocate destination buffer
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: toSize * toSize * 4)
        defer { destData.deallocate() }

        var destBuffer = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(toSize),
            width: vImagePixelCount(toSize),
            rowBytes: toSize * 4
        )

        // Perform Lanczos scaling (high quality)
        // Note: Using ARGB8888 variant but our data is BGRA - this works for scaling
        // as the operation is channel-agnostic
        let error = vImageScale_ARGB8888(
            &sourceBuffer,
            &destBuffer,
            nil,  // Use default temporary buffer
            vImage_Flags(kvImageHighQualityResampling)
        )

        guard error == kvImageNoError else {
            throw DownsampleError.vImageError(error)
        }

        return Data(bytes: destData, count: toSize * toSize * 4)
    }

    /// Downsample with custom interpolation quality
    /// - Parameters:
    ///   - bgraData: Input BGRA data
    ///   - fromSize: Source size
    ///   - toSize: Target size
    ///   - quality: Interpolation quality (.low, .medium, .high)
    /// - Returns: Downsampled data
    public static func downsample(
        _ bgraData: Data,
        from fromSize: Int,
        to toSize: Int,
        quality: InterpolationQuality
    ) throws -> Data {

        // For low/medium quality, use faster algorithms
        let flags: vImage_Flags
        switch quality {
        case .low:
            flags = vImage_Flags(kvImageNoFlags)  // Nearest neighbor
        case .medium:
            flags = vImage_Flags(kvImageEdgeExtend)  // Bilinear
        case .high:
            flags = vImage_Flags(kvImageHighQualityResampling)  // Lanczos
        }

        // Prepare buffers (must be var for inout parameter)
        var sourceBuffer = bgraData.withUnsafeBytes { bytes -> vImage_Buffer in
            vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                height: vImagePixelCount(fromSize),
                width: vImagePixelCount(fromSize),
                rowBytes: fromSize * 4
            )
        }

        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: toSize * toSize * 4)
        defer { destData.deallocate() }

        var destBuffer = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(toSize),
            width: vImagePixelCount(toSize),
            rowBytes: toSize * 4
        )

        let error = vImageScale_ARGB8888(
            &sourceBuffer,
            &destBuffer,
            nil,
            flags
        )

        guard error == kvImageNoError else {
            throw DownsampleError.vImageError(error)
        }

        return Data(bytes: destData, count: toSize * toSize * 4)
    }

    /// Batch downsample multiple frames efficiently
    /// - Parameters:
    ///   - frames: Array of BGRA frame data
    ///   - fromSize: Source size for all frames
    ///   - toSize: Target size for all frames
    /// - Returns: Array of downsampled frames
    public static func batchDownsample(
        _ frames: [Data],
        from fromSize: Int,
        to toSize: Int
    ) async throws -> [Data] {

        // Process frames concurrently but with controlled concurrency
        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            // Limit concurrency to avoid memory pressure
            let maxConcurrency = min(ProcessInfo.processInfo.activeProcessorCount, 4)
            var activeCount = 0
            var frameIndex = 0
            var results: [Data?] = Array(repeating: nil, count: frames.count)

            while frameIndex < frames.count || activeCount > 0 {
                // Start new tasks up to max concurrency
                while activeCount < maxConcurrency && frameIndex < frames.count {
                    let index = frameIndex
                    let frame = frames[index]

                    group.addTask {
                        let downsampled = try downsample(frame, from: fromSize, to: toSize)
                        return (index, downsampled)
                    }

                    activeCount += 1
                    frameIndex += 1
                }

                // Collect completed results
                if let (index, result) = try await group.next() {
                    results[index] = result
                    activeCount -= 1
                }
            }

            // Ensure all results are collected
            return results.compactMap { $0 }
        }
    }
}

// MARK: - Supporting Types

public enum InterpolationQuality {
    case low    // Nearest neighbor - fastest
    case medium // Bilinear - balanced
    case high   // Lanczos - best quality
}

// Error types have been moved to Core/Errors.swift for unified error handling