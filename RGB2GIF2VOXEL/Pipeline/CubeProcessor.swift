//
//  CubeProcessor.swift
//  RGB2GIF2VOXEL
//
//  CRITICAL: Process 1080→256 downsizing, save frames, then quantize
//  All FFI calls happen OFF main thread to prevent crashes
//

import Foundation
import UIKit
import CoreVideo
import OSLog

/// Processes camera frames into 256³ tensor
public actor CubeProcessor {

    // Create these on-demand since they're @MainActor
    private let rustProcessor: RustProcessor
    private let logger = Logger(subsystem: "YIN.RGB2GIF2VOXEL", category: "CubeProcessor")

    public init() async {
        self.rustProcessor = await RustProcessor()
    }

    private var capturedFrames: [Data] = []
    private var downsizedFrames: [Data] = []
    private var isProcessing = false

    /// Process a 1080×1080 frame from camera
    /// - Parameter pixelBuffer: CVPixelBuffer from camera (BGRA format)
    public func processFrame(_ pixelBuffer: CVPixelBuffer) async throws {
        guard !isProcessing else {
            logger.warning("Dropping frame - processing in progress")
            return
        }

        guard capturedFrames.count < 256 else {
            logger.info("Already have 256 frames")
            return
        }

        // Extract BGRA data respecting stride
        let bgraData = try extractBGRAData(from: pixelBuffer)
        capturedFrames.append(bgraData)

        logger.info("📸 Captured frame \(self.capturedFrames.count)/256")

        // Process when we have all frames
        if capturedFrames.count == 256 {
            try await processAllFrames()
        }
    }

    /// Process all 256 frames using new single FFI call
    private func processAllFrames() async throws {
        isProcessing = true
        defer { isProcessing = false }

        logger.info("🚀 Processing 256 frames...")

        // Step 1: Downsize all frames from 1080→256
        let downsized = try await downsizeFrames(capturedFrames)

        // Step 2: SAVE downsized frames to disk (for backup/debugging)
        try await saveFramesWithZig(downsized)
        logger.info("💾 Saved 256 downsized frames to disk")

        // Step 3: Pack frames into contiguous buffer
        let packedBuffer = packFramesForFFI(downsized)

        // Step 4: Single FFI call to Rust for quantization + GIF encoding + tensor
        let result = try await processWithRust(packedBuffer, frameCount: downsized.count)

        logger.info("✅ Rust processing complete:")
        logger.info("   - GIF size: \(result.gifData.count) bytes")
        logger.info("   - Processing time: \(result.processingTimeMs)ms")
        logger.info("   - Palette size: \(result.paletteSizeUsed) colors")

        // Step 5: Save outputs
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let gifsDirectory = documentsPath.appendingPathComponent("gifs")
        try FileManager.default.createDirectory(at: gifsDirectory, withIntermediateDirectories: true)

        // Save GIF
        let gifURL = gifsDirectory.appendingPathComponent("output_\(Date().timeIntervalSince1970).gif")
        try result.gifData.write(to: gifURL)

        // Save tensor if present
        if let tensorData = result.tensorData {
            let tensorURL = gifsDirectory.appendingPathComponent("tensor_\(Date().timeIntervalSince1970).bin")
            try tensorData.write(to: tensorURL)
            logger.info("💾 Saved tensor: \(tensorData.count) bytes")
        }

        logger.info("🎉 Pipeline complete! GIF saved at: \(gifURL.path)")
    }

    /// Extract BGRA data from CVPixelBuffer respecting stride
    private func extractBGRAData(from pixelBuffer: CVPixelBuffer) throws -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw ProcessingError.invalidInput
        }

        // Handle stride - compact if necessary
        if bytesPerRow == width * 4 {
            // Tight packing, can use directly
            return Data(bytes: baseAddress, count: width * height * 4)
        } else {
            // Has padding, need to compact
            var compactData = Data(capacity: width * height * 4)
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

            for row in 0..<height {
                let rowStart = ptr.advanced(by: row * bytesPerRow)
                compactData.append(rowStart, count: width * 4)
            }

            return compactData
        }
    }

    /// Save frames using Swift CBOR for high-performance storage
    private func saveFramesWithZig(_ frames: [Data]) async throws {
        // Create a session ID
        let sessionId = "capture_\(Date().timeIntervalSince1970)"

        // Save frames to disk using SwiftCBORFrameSaver
        // Note: This requires CVPixelBuffer, not Data
        // For now, we'll just save the Data frames to disk directly
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let framesDirectory = documentsPath.appendingPathComponent("frames").appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)

        for (index, frame) in frames.enumerated() {
            let url = framesDirectory.appendingPathComponent("frame_\(String(format: "%03d", index)).bgra")
            try frame.write(to: url)
        }
    }

    /// Downsize frames from 1080→256 using vImage
    private func downsizeFrames(_ frames: [Data]) async throws -> [Data] {
        logger.info("🔽 Downsizing 256 frames using vImage...")

        // Use vImage batch processing for maximum efficiency
        let downsized = try await VImageDownsampler.batchDownsample(
            frames,
            from: 1080,
            to: 256
        )

        logger.info("✅ Downsized all frames to 256×256")
        return downsized
    }

    /// Pack frames into contiguous buffer for FFI
    private func packFramesForFFI(_ frames: [Data]) -> Data {
        var packed = Data(capacity: frames.count * 256 * 256 * 4)
        for frame in frames {
            packed.append(frame)
        }
        return packed
    }

    /// Process with Rust using single FFI call
    private func processWithRust(_ packedFrames: Data, frameCount: Int) async throws -> ProcessResult {
        // Configure options
        let quantizeOpts = QuantizeOpts(
            qualityMin: 70,
            qualityMax: 95,
            speed: 5,
            paletteSize: 256,
            ditheringLevel: 0.8,
            sharedPalette: true
        )

        let gifOpts = GifOpts(
            width: 256,
            height: 256,
            frameCount: UInt16(frameCount),
            fps: 30,
            loopCount: 0,  // Infinite
            optimize: true,
            includeTensor: true  // Generate tensor
        )

        // Single FFI call - use global function from rgb2gif_processor module
        return try await Task.detached(priority: .userInitiated) {
            try RGB2GIF2VOXEL.processAllFrames(
                framesRgba: packedFrames,
                width: 256,
                height: 256,
                frameCount: UInt32(frameCount),
                quantizeOpts: quantizeOpts,
                gifOpts: gifOpts
            )
        }.value
    }
}

// MARK: - Data Structures

/// Metadata for the captured session
struct CubeMetadata {
    let captureDate: Date
    let deviceModel: String
    let frameCount: Int
    let cubeSize: Int
}

// MARK: - Error Types

enum CubeProcessorError: Error {
    case invalidFrameCount
    case processingFailed(String)
    case saveError(String)
}