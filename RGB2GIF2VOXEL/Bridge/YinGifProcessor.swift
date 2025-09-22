//
//  YinGifProcessor.swift
//  RGB2GIF2VOXEL
//
//  Rust FFI processor for frame processing
//

import Foundation

// MARK: - Rust FFI Functions (stubs for now)

@_silgen_name("yingif_processor_new")
func yingif_processor_new() -> OpaquePointer?

@_silgen_name("yingif_processor_free")
func yingif_processor_free(_ processor: OpaquePointer)

@_silgen_name("yingif_process_frame")
func yingif_process_frame(
    _ processor: OpaquePointer?,
    _ bgraData: UnsafePointer<UInt8>,
    _ width: Int32,
    _ height: Int32,
    _ frameIndex: Int32,
    _ indices: UnsafeMutablePointer<UInt8>,
    _ palette: UnsafeMutablePointer<UInt32>,
    _ paletteSize: UnsafeMutablePointer<Int32>
) -> Int32

/// Wrapper for Rust frame processing functions
public class YinGifProcessor {

    private let processor: OpaquePointer?

    public init() {
        // Initialize Rust processor
        processor = yingif_processor_new()
    }

    deinit {
        if let processor = processor {
            yingif_processor_free(processor)
        }
    }

    /// Process a BGRA frame to quantized format
    public func processFrame(
        bgraData: Data,
        width: Int,
        height: Int,
        targetSize: Int,
        paletteSize: Int,
        frameIndex: Int = 0
    ) throws -> QuantizedFrame {
        // Allocate buffers for output
        let pixelCount = targetSize * targetSize
        let indices = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount)
        let palette = UnsafeMutablePointer<UInt32>.allocate(capacity: paletteSize)

        defer {
            indices.deallocate()
            palette.deallocate()
        }

        // Process the frame
        let result = bgraData.withUnsafeBytes { bytes -> Int32 in
            guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }

            var paletteSizeVar = Int32(paletteSize)
            return yingif_process_frame(
                processor,
                ptr,
                Int32(width),
                Int32(height),
                Int32(frameIndex),
                indices,
                palette,
                &paletteSizeVar
            )
        }

        guard result == 0 else {
            throw ProcessingError.ffiError(code: -1)
        }

        // For compatibility, create RGBA data from indices and palette
        // This is a simplified conversion - real implementation would map indices to palette
        var rgbaData = Data(capacity: pixelCount * 4)
        let indicesData = Data(bytes: indices, count: pixelCount)
        let paletteArray = Array(UnsafeBufferPointer(start: palette, count: paletteSize))

        // Convert indexed color to RGBA
        for i in 0..<pixelCount {
            let colorIndex = Int(indices[i]) % paletteArray.count
            let color = paletteArray[colorIndex]
            rgbaData.append(UInt8((color >> 16) & 0xFF)) // R
            rgbaData.append(UInt8((color >> 8) & 0xFF))  // G
            rgbaData.append(UInt8(color & 0xFF))         // B
            rgbaData.append(0xFF)                        // A
        }

        return QuantizedFrame(
            index: frameIndex,
            data: rgbaData,
            width: targetSize,
            height: targetSize
        )
    }

    /// Process frame asynchronously
    public func processFrameAsync(
        bgraData: Data,
        width: Int,
        height: Int,
        targetSize: Int,
        paletteSize: Int
    ) async throws -> QuantizedFrame {
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                throw ProcessingError.invalidInput
            }
            return try self.processFrame(
                bgraData: bgraData,
                width: width,
                height: height,
                targetSize: targetSize,
                paletteSize: paletteSize
            )
        }.value
    }

    // ProcessingError is now defined in CanonicalRustFFI.swift
}

// MARK: - Rust FFI Functions
// These functions are defined in RustFFIStub.swift