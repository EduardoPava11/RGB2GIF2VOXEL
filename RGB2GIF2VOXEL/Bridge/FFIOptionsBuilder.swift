//
//  FFIOptionsBuilder.swift
//  RGB2GIF2VOXEL
//
//  Centralized builder for FFI options with safe Int to UInt16 conversions
//  Prevents type mismatch errors at FFI boundaries
//

import Foundation

/// Centralized builder for FFI structs with safe numeric conversions
/// This ensures Int values from UI/Camera/Processing are safely converted to FFI types
public struct FFIOptionsBuilder {

    // MARK: - Configuration Limits

    /// Maximum supported dimensions (well within UInt16 range)
    private static let maxDimension = 4096

    /// Maximum supported frame count
    private static let maxFrameCount = 1024

    /// Maximum palette size (GIF89a limit)
    private static let maxPaletteSize = 256

    /// Default FPS for GIF animation
    public static let defaultFPS = 25

    // MARK: - GifOpts Builder

    /// Build GifOpts with safe Int to UInt16 conversions
    /// - Parameters:
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    ///   - frameCount: Number of frames
    ///   - fps: Frames per second (default: 25)
    ///   - loopCount: Animation loop count (0 = infinite)
    ///   - optimize: Enable GIF optimization
    ///   - includeTensor: Generate tensor for voxel visualization
    /// - Returns: Properly typed GifOpts for FFI
    public static func buildGifOpts(
        width: Int,
        height: Int,
        frameCount: Int,
        fps: Int = defaultFPS,
        loopCount: Int = 0,
        optimize: Bool = true,
        includeTensor: Bool = true
    ) -> GifOpts {
        // Validate and clamp dimensions
        let safeWidth = clampDimension(width, label: "width")
        let safeHeight = clampDimension(height, label: "height")
        let safeFrameCount = clampFrameCount(frameCount)
        let safeFPS = clampFPS(fps)
        let safeLoopCount = max(0, min(loopCount, Int(UInt16.max)))

        return GifOpts(
            width: UInt16(safeWidth),
            height: UInt16(safeHeight),
            frameCount: UInt16(safeFrameCount),
            fps: UInt16(safeFPS),
            loopCount: UInt16(safeLoopCount),
            optimize: optimize,
            includeTensor: includeTensor
        )
    }

    // MARK: - QuantizeOpts Builder

    /// Build QuantizeOpts with safe conversions
    /// - Parameters:
    ///   - qualityMin: Minimum quality (1-100)
    ///   - qualityMax: Maximum quality (1-100)
    ///   - speed: Processing speed (1=best quality, 10=fastest)
    ///   - paletteSize: Number of colors in palette
    ///   - ditheringLevel: Dithering strength (0.0-1.0)
    ///   - sharedPalette: Use shared palette across frames
    /// - Returns: Properly typed QuantizeOpts for FFI
    public static func buildQuantizeOpts(
        qualityMin: Int = 70,
        qualityMax: Int = 95,
        speed: Int = 5,
        paletteSize: Int = 256,
        ditheringLevel: Float = 0.8,
        sharedPalette: Bool = true
    ) -> QuantizeOpts {
        // Validate and clamp values
        let safeQualityMin = max(1, min(qualityMin, 100))
        let safeQualityMax = max(safeQualityMin, min(qualityMax, 100))
        let safeSpeed = max(1, min(speed, 10))
        let safePaletteSize = clampPaletteSize(paletteSize)
        let safeDitheringLevel = max(0.0, min(ditheringLevel, 1.0))

        return QuantizeOpts(
            qualityMin: UInt8(safeQualityMin),
            qualityMax: UInt8(safeQualityMax),
            speed: Int32(safeSpeed),
            paletteSize: UInt16(safePaletteSize),
            ditheringLevel: safeDitheringLevel,
            sharedPalette: sharedPalette
        )
    }

    // MARK: - N=128 Optimal Presets

    /// Build optimal GifOpts for N=128 configuration
    /// - Parameter frameCount: Number of frames to encode
    /// - Returns: GifOpts configured for N=128 optimal
    public static func buildN128GifOpts(frameCount: Int) -> GifOpts {
        return buildGifOpts(
            width: 128,
            height: 128,
            frameCount: frameCount,
            fps: 25,
            loopCount: 0,
            optimize: true,
            includeTensor: true
        )
    }

    /// Build optimal QuantizeOpts for N=128 configuration
    /// - Returns: QuantizeOpts with proven optimal settings
    public static func buildN128QuantizeOpts() -> QuantizeOpts {
        return buildQuantizeOpts(
            qualityMin: 70,
            qualityMax: 95,
            speed: 5,
            paletteSize: 256,
            ditheringLevel: 0.8,
            sharedPalette: true
        )
    }

    // MARK: - Private Validation Helpers

    private static func clampDimension(_ value: Int, label: String) -> Int {
        if value <= 0 {
            print("⚠️ FFIOptionsBuilder: \(label) \(value) clamped to 1")
            return 1
        }
        if value > maxDimension {
            print("⚠️ FFIOptionsBuilder: \(label) \(value) clamped to \(maxDimension)")
            return maxDimension
        }
        return value
    }

    private static func clampFrameCount(_ value: Int) -> Int {
        if value <= 0 {
            print("⚠️ FFIOptionsBuilder: frameCount \(value) clamped to 1")
            return 1
        }
        if value > maxFrameCount {
            print("⚠️ FFIOptionsBuilder: frameCount \(value) clamped to \(maxFrameCount)")
            return maxFrameCount
        }
        return value
    }

    private static func clampPaletteSize(_ value: Int) -> Int {
        if value < 2 {
            print("⚠️ FFIOptionsBuilder: paletteSize \(value) clamped to 2")
            return 2
        }
        if value > maxPaletteSize {
            print("⚠️ FFIOptionsBuilder: paletteSize \(value) clamped to \(maxPaletteSize)")
            return maxPaletteSize
        }
        return value
    }

    private static func clampFPS(_ value: Int) -> Int {
        if value <= 0 {
            print("⚠️ FFIOptionsBuilder: fps \(value) clamped to 1")
            return 1
        }
        if value > 100 {
            print("⚠️ FFIOptionsBuilder: fps \(value) clamped to 100")
            return 100
        }
        return value
    }
}

// MARK: - Convenience Extensions

extension FFIOptionsBuilder {

    /// ProcessorOptions with N=128 optimal configuration
    public static var n128ProcessorOptions: ProcessorOptions {
        ProcessorOptions(
            quantize: buildN128QuantizeOpts(),
            gif: buildN128GifOpts(frameCount: 128),
            parallel: true
        )
    }

    /// Create ProcessorOptions from current capture settings
    public static func buildProcessorOptions(
        frameCount: Int,
        targetSize: Int = 128,
        paletteSize: Int = 256
    ) -> ProcessorOptions {
        ProcessorOptions(
            quantize: buildQuantizeOpts(paletteSize: paletteSize),
            gif: buildGifOpts(
                width: targetSize,
                height: targetSize,
                frameCount: frameCount
            ),
            parallel: true
        )
    }
}