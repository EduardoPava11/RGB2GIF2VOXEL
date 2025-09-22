// Cube256Config.swift
// Optimized configuration for 256×256×256 HD voxel cubes

import Foundation

/// Configuration constants for 256³ HD quality voxel captures
public struct Cube256Config {
    
    // MARK: - Capture Parameters
    
    /// Target cube dimension (256 frames, 256×256 resolution)
    public static let cubeDimension: Int = 256
    
    /// HD input resolution (assumed after square crop from 1920×1080)
    public static let hdInputResolution: Int = 1080
    
    /// Target frame resolution for processing
    public static let targetResolution: Int = 256
    
    /// Downsample ratio (1080→256 = 4.2:1 ratio)
    public static let downsampleRatio: Double = Double(hdInputResolution) / Double(targetResolution)
    
    /// Frame rate for capture (30fps)
    public static let captureFrameRate: Double = 30.0
    
    /// Capture duration (8.5 seconds for 256 frames at 30fps)
    public static let captureDurationSeconds: Double = Double(cubeDimension) / captureFrameRate
    
    /// Palette size per frame (256 colors for HD quality)
    public static let paletteSize: Int = 256
    
    // MARK: - Memory Budget
    
    /// Bytes per BGRA pixel (4 bytes)
    private static let bytesPerPixel: Int = 4
    
    /// Memory per frame at HD resolution (1080×1080×4 = 4.67MB)
    public static let memoryPerHDFrame: Int = hdInputResolution * hdInputResolution * bytesPerPixel
    
    /// Total capture memory budget (256 frames × 4.67MB = 1.15GB)
    public static let totalCaptureMemoryMB: Double = Double(cubeDimension * memoryPerHDFrame) / (1024 * 1024)
    
    /// Memory per processed frame (256×256×1 = 65KB indexed)
    public static let memoryPerProcessedFrame: Int = targetResolution * targetResolution
    
    /// Total tensor memory (256³ = 16.7MB)
    public static let totalTensorMemoryMB: Double = Double(cubeDimension * cubeDimension * cubeDimension) / (1024 * 1024)
    
    /// Peak memory during processing (capture + tensor + overhead)
    public static let peakMemoryMB: Double = totalCaptureMemoryMB + totalTensorMemoryMB + 50 // 50MB overhead
    
    // MARK: - Performance Targets
    
    /// Target processing time per frame (max 11ms for 90fps processing)
    public static let targetProcessingTimeMs: Double = 11.0
    
    /// GIF export target size range (2-5MB compressed)
    public static let gifTargetSizeMB: ClosedRange<Double> = 2.0...5.0
    
    // MARK: - Quality Settings
    
    /// Lanczos filter quality for 4.2:1 downsample (high quality)
    public static let resampleQuality: String = "Lanczos3"
    
    /// NeuQuant quality parameter (10 = high quality, lower = better)
    public static let neuQuantQuality: Int = 10
    
    // MARK: - Validation
    
    /// Check if device can handle 256³ capture
    public static func validateDeviceCapability() -> (canCapture: Bool, reason: String?) {
        let availableMemoryMB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        let recommendedMinMemory: UInt64 = 2048 // 2GB minimum
        
        if availableMemoryMB < recommendedMinMemory {
            return (false, "Device has \(availableMemoryMB)MB RAM, need \(recommendedMinMemory)MB minimum")
        }
        
        if peakMemoryMB > Double(availableMemoryMB) * 0.6 { // Use max 60% of available memory
            return (false, "Peak memory (\(Int(peakMemoryMB))MB) exceeds 60% of available RAM")
        }
        
        return (true, nil)
    }
    
    /// Get user-friendly capture summary
    public static var captureSummary: String {
        return """
        256³ HD Voxel Capture
        • Resolution: \(hdInputResolution)×\(hdInputResolution) → \(targetResolution)×\(targetResolution)
        • Frames: \(cubeDimension) frames
        • Duration: \(String(format: "%.1f", captureDurationSeconds)) seconds
        • Memory: \(String(format: "%.1f", totalCaptureMemoryMB))GB capture, \(String(format: "%.0f", totalTensorMemoryMB))MB tensor
        • Quality: \(paletteSize) colors/frame, \(resampleQuality) resampling
        """
    }
}

// MARK: - Configuration Validation

extension Cube256Config {
    
    /// Verify configuration consistency
    public static func validateConfiguration() -> Bool {
        // Check dimensions make sense
        guard cubeDimension > 0 && targetResolution > 0 && hdInputResolution > 0 else {
            return false
        }
        
        // Check downsample ratio is reasonable (2:1 to 8:1 range)
        guard downsampleRatio >= 2.0 && downsampleRatio <= 8.0 else {
            return false
        }
        
        // Check capture duration is reasonable (5-15 seconds)
        guard captureDurationSeconds >= 5.0 && captureDurationSeconds <= 15.0 else {
            return false
        }
        
        // Check memory requirements are within iOS limits
        guard peakMemoryMB <= 1800 else { // Conservative iOS limit
            return false
        }
        
        return true
    }
    
    /// Performance warning thresholds
    public static func getPerformanceWarnings() -> [String] {
        var warnings: [String] = []
        
        if totalCaptureMemoryMB > 1000 {
            warnings.append("High memory usage: \(Int(totalCaptureMemoryMB))MB capture buffer")
        }
        
        if captureDurationSeconds > 10 {
            warnings.append("Long capture duration: \(String(format: "%.1f", captureDurationSeconds))s")
        }
        
        if downsampleRatio > 6.0 {
            warnings.append("Aggressive downsampling: \(String(format: "%.1f", downsampleRatio)):1 ratio")
        }
        
        return warnings
    }
}