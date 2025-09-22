//
//  LegacyCompatibility.swift
//  RGB2GIF2VOXEL
//
//  Compatibility layer for old API types
//  This allows gradual migration from old to new API
//

import Foundation

// MARK: - Type Aliases for Backwards Compatibility

/// Legacy type that represented a single quantized frame
/// Now we process all frames at once in a single buffer
public struct QuantizedFrame {
    public let index: Int
    public let data: Data
    public let width: Int
    public let height: Int

    public init(index: Int, data: Data, width: Int, height: Int) {
        self.index = index
        self.data = data
        self.width = width
        self.height = height
    }

    /// Convert array of QuantizedFrames to single buffer for new API
    public static func packFrames(_ frames: [QuantizedFrame]) -> Data {
        var packed = Data()
        for frame in frames.sorted(by: { $0.index < $1.index }) {
            packed.append(frame.data)
        }
        return packed
    }
}

/// Legacy ProcessorOptions - now split into QuantizeOpts and GifOpts
public struct ProcessorOptions {
    public let quantize: QuantizeOpts
    public let gif: GifOpts
    public let parallel: Bool

    public init(quantize: QuantizeOpts, gif: GifOpts, parallel: Bool = true) {
        self.quantize = quantize
        self.gif = gif
        self.parallel = parallel
    }
}

/// Legacy QuantizeResult - functionality now integrated into ProcessResult
public struct QuantizeResult {
    public let indices: [UInt8]
    public let palette: [RGBAColor]
    public let width: UInt32
    public let height: UInt32
    public let frameCount: UInt32

    public init(indices: [UInt8], palette: [RGBAColor], width: UInt32, height: UInt32, frameCount: UInt32) {
        self.indices = indices
        self.palette = palette
        self.width = width
        self.height = height
        self.frameCount = frameCount
    }
}

/// Legacy RGBA color representation
public struct RGBAColor {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    public let a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// Legacy TensorShape - tensor building now integrated into main processing
public struct TensorShape {
    public let width: UInt32
    public let height: UInt32
    public let frames: UInt32

    public init(width: UInt32, height: UInt32, frames: UInt32) {
        self.width = width
        self.height = height
        self.frames = frames
    }
}

// MARK: - Legacy Function Adapters

/// Adapter for old processFramesToGif function
/// Redirects to new processAllFrames API
public func processFramesToGif(
    framesRgba: [UInt8],
    width: UInt32,
    height: UInt32,
    frameCount: UInt32,
    options: ProcessorOptions
) throws -> [UInt8] {
    // Convert to new API call
    let result = try processAllFrames(
        framesRgba: Data(framesRgba),
        width: width,
        height: height,
        frameCount: frameCount,
        quantizeOpts: options.quantize,
        gifOpts: options.gif
    )
    return Array(result.gifData)
}

/// Adapter for old quantizeFrames function
/// The new API doesn't expose separate quantization
public func quantizeFrames(
    framesRgba: [UInt8],
    width: UInt32,
    height: UInt32,
    frameCount: UInt32,
    options: QuantizeOpts
) throws -> QuantizeResult {
    // Create minimal GifOpts for processing
    let gifOpts = GifOpts(
        width: UInt16(width),
        height: UInt16(height),
        frameCount: UInt16(frameCount),
        fps: 30,
        loopCount: 0,
        optimize: false,
        includeTensor: false
    )

    // Process frames to get palette info
    let result = try processAllFrames(
        framesRgba: Data(framesRgba),
        width: width,
        height: height,
        frameCount: frameCount,
        quantizeOpts: options,
        gifOpts: gifOpts
    )

    // Return mock result with palette size info
    // Note: Actual indices and palette not available in new API
    return QuantizeResult(
        indices: [],
        palette: [],
        width: width,
        height: height,
        frameCount: frameCount
    )
}

/// Adapter for old buildCubeTensor function
/// Tensor building now integrated into main processing
public func buildCubeTensor(
    framesRgba: [UInt8],
    shape: TensorShape
) throws -> [UInt8] {
    // Create options with tensor generation enabled
    let quantizeOpts = QuantizeOpts(
        qualityMin: 70,
        qualityMax: 100,
        speed: 5,
        paletteSize: 256,
        ditheringLevel: 1.0,
        sharedPalette: true
    )

    let gifOpts = GifOpts(
        width: UInt16(shape.width),
        height: UInt16(shape.height),
        frameCount: UInt16(shape.frames),
        fps: 30,
        loopCount: 0,
        optimize: false,
        includeTensor: true  // Enable tensor generation
    )

    let result = try processAllFrames(
        framesRgba: Data(framesRgba),
        width: shape.width,
        height: shape.height,
        frameCount: shape.frames,
        quantizeOpts: quantizeOpts,
        gifOpts: gifOpts
    )

    // Return tensor data or empty array
    return Array(result.tensorData ?? Data())
}