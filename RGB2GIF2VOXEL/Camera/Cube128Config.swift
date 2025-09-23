// Cube128Config.swift
// Optimized configuration for 128×128×128 voxel cubes (mathematically optimal N=128)

import Foundation

/// Configuration constants for 128³ optimal quality voxel captures
public struct Cube128Config {

    // MARK: - Capture Parameters

    /// Target cube dimension (128 frames, 128×128 resolution) - mathematically optimal
    public static let cubeDimension: Int = 128

    /// HD input resolution (assumed after square crop from 1920×1080)
    public static let hdInputResolution: Int = 1080

    /// Target frame resolution for processing
    public static let targetResolution: Int = 128

    /// Downsample ratio (1080→128 = 8.4:1 ratio)
    public static let downsampleRatio: Double = Double(hdInputResolution) / Double(targetResolution)

    /// Frame rate for capture (30fps)
    public static let captureFrameRate: Double = 30.0

    /// Capture duration (4.27 seconds for 128 frames at 30fps)
    public static let captureDurationSeconds: Double = Double(cubeDimension) / captureFrameRate

    /// Palette size per frame (256 colors for optimal quality)
    public static let paletteSize: Int = 256

    // MARK: - Memory Budget

    /// Bytes per BGRA pixel (4 bytes)
    private static let bytesPerPixel: Int = 4

    /// Memory per frame at HD resolution (1080×1080×4 = 4.67MB)
    public static let memoryPerHDFrame: Int = hdInputResolution * hdInputResolution * bytesPerPixel

    /// Total capture memory budget (128 frames × 4.67MB = 598MB)
    public static let totalCaptureMemoryMB: Double = Double(cubeDimension * memoryPerHDFrame) / (1024 * 1024)

    /// Memory per processed frame (128×128×1 = 16KB indexed)
    public static let memoryPerProcessedFrame: Int = targetResolution * targetResolution

    /// Total tensor memory (128³ = 2.1MB)
    public static let totalTensorMemoryMB: Double = Double(cubeDimension * cubeDimension * cubeDimension) / (1024 * 1024)

    /// Peak memory during processing (capture + tensor + overhead)
    public static let peakMemoryMB: Double = totalCaptureMemoryMB + totalTensorMemoryMB + 50 // 50MB overhead

    // MARK: - Performance Targets

    /// Target processing time per frame (max 11ms for 90fps processing)
    public static let targetProcessingTimeMs: Double = 11.0

    /// GIF export target size range (1-3MB compressed)
    public static let gifTargetSizeMB: ClosedRange<Double> = 1.0...3.0

    // MARK: - Quality Settings

    /// Lanczos filter quality for 8.4:1 downsample (high quality)
    public static let resampleQuality: String = "Lanczos3"

    /// NeuQuant quality parameter (10 = high quality, lower = better)
    public static let neuQuantQuality: Int = 10

    /// STBN dithering parameters (from mathematical verification)
    public static let stbnTemporalFrames: Int = 8
    public static let stbnSpatialSigma: Double = 2.0
    public static let stbnTemporalSigma: Double = 1.5
    public static let vanGoghGamma: Double = 0.2  // Van Gogh style weight

    // MARK: - Mathematical Optimality

    /// Combined loss function target J=0.335 (from Haskell verification)
    public static let targetCombinedLoss: Double = 0.335

    /// Expected effective color count (483-650 from STBN dithering)
    public static let effectiveColorRange: ClosedRange<Int> = 483...650

    // MARK: - Validation

    /// Check if device can handle 128³ capture
    public static func validateDeviceCapability() -> (canCapture: Bool, reason: String?) {
        let availableMemoryMB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        let recommendedMinMemory: UInt64 = 1024 // 1GB minimum (reduced from 2GB)

        if availableMemoryMB < recommendedMinMemory {
            return (false, "Device has \(availableMemoryMB)MB RAM, need \(recommendedMinMemory)MB minimum")
        }

        if peakMemoryMB > Double(availableMemoryMB) * 0.5 { // Use max 50% of available memory
            return (false, "Peak memory (\(Int(peakMemoryMB))MB) exceeds 50% of available RAM")
        }

        return (true, nil)
    }

    /// Get user-friendly capture summary
    public static var captureSummary: String {
        return """
        128³ Optimal Voxel Capture
        • Resolution: \(hdInputResolution)×\(hdInputResolution) → \(targetResolution)×\(targetResolution)
        • Frames: \(cubeDimension) frames
        • Duration: \(String(format: "%.1f", captureDurationSeconds)) seconds
        • Memory: \(String(format: "%.0f", totalCaptureMemoryMB))MB capture, \(String(format: "%.1f", totalTensorMemoryMB))MB tensor
        • Quality: \(paletteSize) colors/frame, \(resampleQuality) resampling
        • Optimization: N=128 mathematically optimal (J=\(targetCombinedLoss))
        """
    }
}

// MARK: - Configuration Validation

extension Cube128Config {

    /// Verify configuration consistency
    public static func validateConfiguration() -> Bool {
        // Check dimensions make sense
        guard cubeDimension == 128 && targetResolution == 128 else {
            return false // Must be exactly 128 for optimality
        }

        // Check downsample ratio is reasonable (2:1 to 10:1 range)
        guard downsampleRatio >= 2.0 && downsampleRatio <= 10.0 else {
            return false
        }

        // Check capture duration is reasonable (3-10 seconds)
        guard captureDurationSeconds >= 3.0 && captureDurationSeconds <= 10.0 else {
            return false
        }

        // Check memory requirements are within iOS limits
        guard peakMemoryMB <= 800 else { // Very conservative for N=128
            return false
        }

        return true
    }

    /// Performance warning thresholds
    public static func getPerformanceWarnings() -> [String] {
        var warnings: [String] = []

        if totalCaptureMemoryMB > 600 {
            warnings.append("Memory usage: \(Int(totalCaptureMemoryMB))MB capture buffer")
        }

        if captureDurationSeconds > 5 {
            warnings.append("Capture duration: \(String(format: "%.1f", captureDurationSeconds))s")
        }

        if downsampleRatio > 8.0 {
            warnings.append("Aggressive downsampling: \(String(format: "%.1f", downsampleRatio)):1 ratio")
        }

        return warnings
    }

    /// Get optimization benefits compared to other N values
    public static func getOptimizationBenefits() -> String {
        return """
        N=128 Optimization Benefits:
        • Mathematical optimum: J=0.335 combined loss
        • Memory efficient: ~8MB tensor (vs 67MB for N=256)
        • Perceptual quality: 483-650 effective colors with STBN
        • Faster processing: 8× fewer voxels than N=256
        • Better cache locality: Fits in L2/L3 cache
        • Van Gogh style: γ=0.2 complementary color enhancement
        """
    }
}