//
//  FloatDoubleConversions.swift
//  RGB2GIF2VOXEL
//
//  Type conversion helpers for Float/Double boundaries
//  Provides safe conversions between UI (Double) and FFI (Float) layers
//

import Foundation

/// Type conversion utilities for numeric boundaries
public struct NumericConversions {

    // MARK: - Quality Level Conversions

    /// Convert quality level from UI (Double) to FFI (Float)
    /// - Parameter quality: Quality level as Double (0.0-1.0)
    /// - Returns: Quality level as Float for FFI
    public static func qualityToFFI(_ quality: Double) -> Float {
        Float(max(0.0, min(1.0, quality)))
    }

    /// Convert quality level from FFI (Float) to UI (Double)
    /// - Parameter quality: Quality level as Float from FFI
    /// - Returns: Quality level as Double for UI
    public static func qualityFromFFI(_ quality: Float) -> Double {
        Double(quality)
    }

    // MARK: - Progress Conversions

    /// Convert progress from UI (Double) to FFI (Float)
    /// - Parameter progress: Progress as Double (0.0-1.0)
    /// - Returns: Progress as Float for FFI
    public static func progressToFFI(_ progress: Double) -> Float {
        Float(max(0.0, min(1.0, progress)))
    }

    /// Convert progress from FFI (Float) to UI (Double)
    /// - Parameter progress: Progress as Float from FFI
    /// - Returns: Progress as Double for UI
    public static func progressFromFFI(_ progress: Float) -> Double {
        Double(progress)
    }

    // MARK: - Processing Time Conversions

    /// Convert processing time from FFI (Float ms) to UI (TimeInterval seconds)
    /// - Parameter timeMs: Time in milliseconds as Float
    /// - Returns: TimeInterval in seconds
    public static func processingTimeFromFFI(_ timeMs: Float) -> TimeInterval {
        Double(timeMs) / 1000.0
    }

    /// Convert processing time from UI (TimeInterval) to FFI (Float ms)
    /// - Parameter time: TimeInterval in seconds
    /// - Returns: Time in milliseconds as Float
    public static func processingTimeToFFI(_ time: TimeInterval) -> Float {
        Float(time * 1000.0)
    }

    // MARK: - Dithering Level Conversions

    /// Convert dithering level from configuration (Double) to FFI (Float)
    /// - Parameter level: Dithering level as Double (0.0-1.0)
    /// - Returns: Dithering level as Float for FFI
    public static func ditheringToFFI(_ level: Double) -> Float {
        Float(max(0.0, min(1.0, level)))
    }

    // MARK: - Batch Conversion Helpers

    /// Convert array of progress values from Double to Float
    /// - Parameter values: Array of Double progress values
    /// - Returns: Array of Float progress values
    public static func progressArrayToFFI(_ values: [Double]) -> [Float] {
        values.map { progressToFFI($0) }
    }

    /// Convert array of progress values from Float to Double
    /// - Parameter values: Array of Float progress values
    /// - Returns: Array of Double progress values
    public static func progressArrayFromFFI(_ values: [Float]) -> [Double] {
        values.map { progressFromFFI($0) }
    }
}

// MARK: - Extensions for Common Types

extension ProcessingConfiguration {
    /// Get quality level as Float for FFI
    public var qualityLevelForFFI: Float {
        NumericConversions.qualityToFFI(qualityLevel)
    }
}

extension ProcessingState {
    /// Get progress as Float for FFI (if in processing state)
    public var progressForFFI: Float? {
        switch self {
        case .processing(_, let progress):
            return NumericConversions.progressToFFI(progress)
        default:
            return nil
        }
    }
}

// MARK: - FFI Builder Extension

extension FFIOptionsBuilder {
    /// Build QuantizeOpts from ProcessingConfiguration
    /// - Parameter config: Processing configuration with Double values
    /// - Returns: QuantizeOpts with proper Float values
    public static func buildQuantizeOpts(from config: ProcessingConfiguration) -> QuantizeOpts {
        let ditheringLevel = config.enableDithering ?
            NumericConversions.ditheringToFFI(config.qualityLevel) : 0.0

        // Map quality level (0.0-1.0) to quality range (1-100)
        let qualityPercent = Int(config.qualityLevel * 100)
        let qualityMin = max(1, qualityPercent - 10)
        let qualityMax = min(100, qualityPercent + 5)

        return buildQuantizeOpts(
            qualityMin: qualityMin,
            qualityMax: qualityMax,
            speed: 5,
            paletteSize: 256,
            ditheringLevel: ditheringLevel,
            sharedPalette: true
        )
    }
}