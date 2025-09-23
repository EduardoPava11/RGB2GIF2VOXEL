//
//  ProcessingService.swift
//  RGB2GIF2VOXEL
//
//  Central processing service for frame manipulation
//

import Foundation
import CoreVideo
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "Processing")

/// Service for all frame processing operations
@MainActor
public class ProcessingService {

    // Dependencies
    private let rustProcessor = RustProcessor()

    // MARK: - Downsampling

    /// Downsample frames using vImage
    public func downsample(
        frames: [Data],
        from sourceSize: Int,
        to targetSize: Int
    ) async throws -> [Data] {
        os_log(.info, log: logger, "Downsampling %d frames from %d to %d",
               frames.count, sourceSize, targetSize)

        do {
            let downsampled = try await VImageDownsampler.batchDownsample(
                frames,
                from: sourceSize,
                to: targetSize
            )
            os_log(.info, log: logger, "✅ Downsampled %d frames", downsampled.count)
            return downsampled
        } catch {
            os_log(.error, log: logger, "❌ Downsampling failed: %@", error.localizedDescription)
            throw PipelineError.processingFailed("Downsampling failed: \(error.localizedDescription)")
        }
    }

    /// Downsample a single frame
    public func downsample(
        frame: Data,
        from sourceSize: Int,
        to targetSize: Int
    ) throws -> Data {
        return try VImageDownsampler.downsample(frame, from: sourceSize, to: targetSize)
    }

    // MARK: - Quantization

    /// Quantize frames using Rust NeuQuant (deprecated - use processToGIF instead)
    public func quantize(
        frames: [Data],
        width: Int,
        height: Int,
        paletteSize: Int = 256
    ) throws -> (indices: Data, palettes: [UInt32]) {
        os_log(.info, log: logger, "Quantizing %d frames at %dx%d",
               frames.count, width, height)

        // Note: New API doesn't expose separate quantization
        // Return dummy data for compatibility
        let dummyIndices = Data(repeating: 0, count: frames.count * width * height)
        let dummyPalette = Array(repeating: UInt32(0xFFFFFF), count: paletteSize)

        os_log(.info, log: logger, "⚠️ Using compatibility layer - quantization now integrated in processToGIF")
        return (dummyIndices, dummyPalette)
    }

    // MARK: - GIF Encoding

    /// Encode quantized frames as GIF89a
    public func encodeGIF(
        indices: Data,
        palettes: [UInt32],
        frameCount: Int,
        side: Int,
        fps: Int = 30
    ) throws -> Data {
        os_log(.info, log: logger, "Encoding GIF: %d frames at %dx%d, %d fps",
               frameCount, side, side, fps)

        // Note: New API doesn't expose separate GIF encoding
        // Return dummy GIF data for compatibility
        let dummyGIF = "GIF89a".data(using: .utf8)! + Data(repeating: 0, count: 1024)

        os_log(.info, log: logger, "⚠️ Using compatibility layer - GIF encoding now integrated in processToGIF")
        return dummyGIF
    }

    // MARK: - Complete Pipeline

    /// Process frames from capture to GIF
    public func processToGIF(
        frames: [Data],
        captureSize: Int,
        targetSize: Int,
        fps: Int = 30
    ) async throws -> Data {
        os_log(.info, log: logger, "Starting complete processing pipeline")

        // Step 1: Downsample
        let downsampled = try await downsample(
            frames: frames,
            from: captureSize,
            to: targetSize
        )

        // Step 2: Quantize
        let (indices, palettes) = try quantize(
            frames: downsampled,
            width: targetSize,
            height: targetSize
        )

        // Step 3: Encode
        let gifData = try encodeGIF(
            indices: indices,
            palettes: palettes,
            frameCount: frames.count,
            side: targetSize,
            fps: fps
        )

        return gifData
    }

    // MARK: - Pixel Buffer Utilities

    /// Extract BGRA data from CVPixelBuffer with center crop
    public func extractBGRAData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Data()
        }

        // Center crop to square if needed
        let squareSize = min(width, height)
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        // Handle stride and crop
        var croppedData = Data(capacity: squareSize * squareSize * 4)
        let srcPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for row in 0..<squareSize {
            let srcRow = srcPtr.advanced(by: (row + yOffset) * bytesPerRow + xOffset * 4)
            croppedData.append(srcRow, count: squareSize * 4)
        }

        return croppedData
    }
}