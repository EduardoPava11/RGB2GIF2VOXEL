import Foundation

// Swift wrapper for GIF89a encoding using Rust FFI stubs
// Uses CubeTensorData from Models/CubeTensorData.swift
// Note: Using stubs from RustFFIStub.swift to avoid duplicate symbols

// MARK: - Rust FFI Functions (stubs for now)

@_silgen_name("yingif_estimate_gif_size")
func yingif_estimate_gif_size(_ size: Int32, _ paletteSize: Int32) -> Int32

@_silgen_name("yingif_create_gif89a")
func yingif_create_gif89a(
    _ indices: UnsafePointer<UInt8>,
    _ palette: UnsafePointer<UInt32>,
    _ paletteSize: Int32,
    _ width: Int32,
    _ height: Int32,
    _ frameCount: Int32,
    _ delayMs: Int32,
    _ outputBuffer: UnsafeMutablePointer<UInt8>,
    _ bufferSize: Int32,
    _ actualSize: UnsafeMutablePointer<Int32>
) -> Int32

class GIF89aEncoder {

    /// Encode cube tensor data to GIF89a format optimized for 256×256×256 cubes
    /// - Parameters:
    ///   - tensor: CubeTensorData containing indices and palette
    ///   - delayMs: Frame delay in milliseconds (33ms = 30fps, 40ms = 25fps)
    /// - Returns: Compressed GIF data targeting 2-5MB file size
    static func encode(tensor: CubeTensorData, delayMs: Int = 33) -> Data? {
        // Validate 256³ cube expectations
        guard tensor.size == 256 else {
            print("GIF encoder optimized for 256×256×256 cubes, got \(tensor.size)³")
            return nil
        }
        
        // Validate data consistency
        let expectedPixels = tensor.size * tensor.size * tensor.size
        guard tensor.indices.count == expectedPixels else {
            print("Indices count mismatch: expected \(expectedPixels), got \(tensor.indices.count)")
            return nil
        }
        
        // Estimate buffer size for 256×256×256 cube (targets 2-5MB)
        // Conservative estimate: header + palette + compressed frame data
        let frameSize = tensor.size * tensor.size  // 65,536 pixels per frame
        let frameCount = tensor.size  // 256 frames
        let estimatedSize = max(
            Int(yingif_estimate_gif_size(
                Int32(tensor.size),
                Int32(tensor.paletteSize)
            )),
            // Fallback calculation for 256³
            800 + (tensor.paletteSize * 3) + (frameSize * frameCount * 12 / 10)
        )
        
        print("Encoding 256×256×256 cube to GIF89a (estimated size: \(estimatedSize / 1024)KB)")

        // Allocate output buffer with extra headroom for compression variations
        var outputBuffer = Data(count: estimatedSize + 1024)
        var actualSize: Int32 = 0

        // Convert Swift arrays to contiguous memory for FFI
        let bufferCapacity = Int32(outputBuffer.count)  // Copy to avoid overlapping access
        let result = tensor.indices.withUnsafeBufferPointer { indicesPtr in
            tensor.palette.withUnsafeBufferPointer { palettePtr in
                outputBuffer.withUnsafeMutableBytes { outputPtr in
                    yingif_create_gif89a(
                        indicesPtr.baseAddress!,
                        palettePtr.baseAddress!,
                        Int32(tensor.paletteSize),  // paletteSize
                        Int32(tensor.size),          // width
                        Int32(tensor.size),          // height
                        Int32(tensor.size),          // frameCount
                        Int32(delayMs),              // delayMs
                        outputPtr.bindMemory(to: UInt8.self).baseAddress!,  // outputBuffer
                        bufferCapacity,              // bufferSize
                        &actualSize                  // actualSize
                    )
                }
            }
        }

        // Check encoding result
        if result == 0 && actualSize > 0 {
            // Resize to actual size and validate target range
            outputBuffer.count = Int(actualSize)
            let fileSizeMB = Double(actualSize) / (1024 * 1024)
            print("GIF encoding successful: \(actualSize) bytes (\(String(format: "%.2f", fileSizeMB))MB)")
            
            // Warn if outside target range
            if fileSizeMB < 2.0 {
                print("Warning: GIF size below 2MB target, may indicate compression artifacts")
            } else if fileSizeMB > 5.0 {
                print("Warning: GIF size above 5MB target, consider palette optimization")
            }
            
            return outputBuffer
        } else {
            print("GIF encoding failed with error: \(result)")
            return nil
        }
    }
}