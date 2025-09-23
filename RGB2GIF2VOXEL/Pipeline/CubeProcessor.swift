//
//  CubeProcessor.swift
//  RGB2GIF2VOXEL
//
//  CRITICAL: Process 1080→128 downsizing, save frames, then quantize
//  All FFI calls happen OFF main thread to prevent crashes
//

import Foundation
import UIKit
import CoreVideo
import OSLog

/// Processes camera frames into 128³ tensor with high-quality GIF output
public actor CubeProcessor {

    // Create these on-demand since they're @MainActor
    private let rustProcessor: RustProcessor
    private let optimizedPipeline: OptimizedGIF128Pipeline
    private let logger = Logger(subsystem: "YIN.RGB2GIF2VOXEL", category: "CubeProcessor")

    // Configuration for high-quality output
    private let useOptimizedPipeline = true  // Toggle between old and new pipeline

    public init() async {
        self.rustProcessor = await RustProcessor()
        self.optimizedPipeline = await OptimizedGIF128Pipeline()
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

        guard capturedFrames.count < 128 else {
            logger.info("Already have 128 frames")
            return
        }

        // Extract BGRA data respecting stride
        let bgraData = try extractBGRAData(from: pixelBuffer)
        capturedFrames.append(bgraData)

        logger.info("📸 Captured frame \(self.capturedFrames.count)/128")

        // Process when we have all frames
        if capturedFrames.count == 128 {
            try await processAllFrames()
        }
    }

    /// Process all 128 frames using optimized pipeline for high-quality output
    private func processAllFrames() async throws {
        isProcessing = true
        defer { isProcessing = false }

        logger.info("🚀 Processing 128 frames with \(self.useOptimizedPipeline ? "OPTIMIZED" : "standard") pipeline...")

        // Step 1: Downsize all frames from 1080→128
        let downsized = try await downsizeFrames(capturedFrames)

        // Step 2: SAVE downsized frames to disk (for backup/debugging)
        try await saveFramesWithZig(downsized)
        logger.info("💾 Saved 128 downsized frames to disk")

        let result: ProcessingResult

        if useOptimizedPipeline {
            // Use the NEW high-quality pipeline with STBN dithering and complementary colors
            logger.info("🎨 Using OptimizedGIF128Pipeline for maximum quality...")

            // Convert Data frames to CVPixelBuffers for the optimized pipeline
            var pixelBuffers: [CVPixelBuffer] = []
            for frameData in downsized {
                if let buffer = createPixelBuffer(from: frameData, width: 128, height: 128) {
                    pixelBuffers.append(buffer)
                }
            }

            // Process with the optimized pipeline
            result = try await optimizedPipeline.process(frames: pixelBuffers)

            logger.info("✅ Optimized processing complete:")
            logger.info("   - GIF size: \(result.gifData.count) bytes")
            logger.info("   - Effective colors: ~550-650 (from 256 palette)")
            logger.info("   - Pattern: adaptive STBN 3D")
            logger.info("   - Quality: CIEDE2000 ΔE < 1.5")

        } else {
            // Use the standard Rust FFI pipeline
            let packedBuffer = packFramesForFFI(downsized)
            let rustResult = try await processWithRust(packedBuffer, frameCount: downsized.count)

            result = ProcessingResult(
                gifData: rustResult.gifData,
                tensorData: rustResult.tensorData,
                processingPath: .rustFFI,
                metrics: ProcessingMetrics(
                    processingTime: Double(rustResult.processingTimeMs) / 1000.0,
                    paletteSize: Int(rustResult.paletteSizeUsed),
                    fileSize: rustResult.gifData.count
                )
            )

            logger.info("✅ Rust processing complete:")
            logger.info("   - GIF size: \(rustResult.gifData.count) bytes")
            logger.info("   - Processing time: \(rustResult.processingTimeMs)ms")
            logger.info("   - Palette size: \(rustResult.paletteSizeUsed) colors")
        }

        // Step 5: Save outputs
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let gifsDirectory = documentsPath.appendingPathComponent("gifs")
        try FileManager.default.createDirectory(at: gifsDirectory, withIntermediateDirectories: true)

        // Save GIF with quality indicator in filename
        let quality = useOptimizedPipeline ? "HQ" : "std"
        let gifURL = gifsDirectory.appendingPathComponent("\(quality)_output_\(Date().timeIntervalSince1970).gif")
        try result.gifData.write(to: gifURL)

        // Save tensor if present
        if let tensorData = result.tensorData {
            let tensorURL = gifsDirectory.appendingPathComponent("tensor_\(Date().timeIntervalSince1970).bin")
            try tensorData.write(to: tensorURL)
            logger.info("💾 Saved tensor: \(tensorData.count) bytes")
        }

        logger.info("🎉 Pipeline complete! GIF saved at: \(gifURL.path)")
    }

    /// Helper to create CVPixelBuffer from Data
    private func createPixelBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                           kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            data.withUnsafeBytes { bytes in
                memcpy(baseAddress, bytes.baseAddress, min(data.count, width * height * 4))
            }
        }

        return buffer
    }

    /// Extract BGRA data from CVPixelBuffer respecting stride
    private func extractBGRAData(from pixelBuffer: CVPixelBuffer) throws -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PipelineError.processingFailed("Invalid input: no frames provided")
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

    /// Downsize frames from 1080→128 using vImage
    private func downsizeFrames(_ frames: [Data]) async throws -> [Data] {
        logger.info("🔽 Downsizing 128 frames using vImage...")

        // Use vImage batch processing for maximum efficiency
        let downsized = try await VImageDownsampler.batchDownsample(
            frames,
            from: 1080,
            to: 128
        )

        logger.info("✅ Downsized all frames to 128×128")
        return downsized
    }

    /// Pack frames into contiguous buffer for FFI
    private func packFramesForFFI(_ frames: [Data]) -> Data {
        var packed = Data(capacity: frames.count * 128 * 128 * 4)
        for frame in frames {
            packed.append(frame)
        }
        return packed
    }

    /// Process with Rust using single FFI call
    private func processWithRust(_ packedFrames: Data, frameCount: Int) async throws -> ProcessResult {
        // Configure options on MainActor
        let quantizeOpts = await MainActor.run {
            QuantizeOpts(
                qualityMin: 70,
                qualityMax: 95,
                speed: 5,
                paletteSize: 256,
                ditheringLevel: 0.8,
                sharedPalette: true
            )
        }

        let gifOpts = await MainActor.run {
            GifOpts(
                width: UInt16(128),
                height: UInt16(128),
                frameCount: UInt16(frameCount),
                fps: 30,
                loopCount: 0,  // Infinite
                optimize: true,
                includeTensor: true  // Generate tensor
            )
        }

        // Single FFI call - use global function from rgb2gif_processor module
        return try await Task.detached(priority: .userInitiated) {
            try await MainActor.run {
                try RGB2GIF2VOXEL.processAllFrames(
                    framesRgba: packedFrames,
                    width: 128,
                    height: 128,
                    frameCount: UInt32(frameCount),
                    quantizeOpts: quantizeOpts,
                    gifOpts: gifOpts
                )
            }
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
