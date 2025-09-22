//
//  TestPipeline.swift
//  RGB2GIF2VOXEL
//
//  End-to-end test of camera → downsample → FFI → GIF pipeline
//

import Foundation
import UIKit

/// Test harness for complete pipeline
class TestPipeline {

    /// Generate test frames and process them through the complete pipeline
    static func runTest() async throws {
        print("🧪 Starting pipeline test...")

        // 1. Generate 256 test frames at 1080×1080
        let testFrames = generateTestFrames()
        print("✅ Generated \(testFrames.count) test frames at 1080×1080")

        // 2. Downsample to 256×256 using vImage
        let downsampledFrames = try await VImageDownsampler.batchDownsample(
            testFrames,
            from: 1080,
            to: 256
        )
        print("✅ Downsampled to 256×256")

        // 3. Pack into contiguous buffer for FFI
        let packedBuffer = packFrames(downsampledFrames)
        print("✅ Packed \(packedBuffer.count) bytes for FFI")

        // 4. Call Rust via single FFI
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
            frameCount: 256,
            fps: 30,
            loopCount: 0,
            optimize: true,
            includeTensor: true
        )

        let result = try processAllFrames(
            framesRgba: packedBuffer,
            width: 256,
            height: 256,
            frameCount: 256,
            quantizeOpts: quantizeOpts,
            gifOpts: gifOpts
        )

        print("✅ Rust processing complete:")
        print("   - GIF size: \(result.gifData.count) bytes")
        print("   - Processing time: \(result.processingTimeMs)ms")
        print("   - Palette size: \(result.paletteSizeUsed) colors")

        // 5. Save GIF to documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let gifURL = documentsPath.appendingPathComponent("test_output.gif")
        try result.gifData.write(to: gifURL)
        print("✅ Saved GIF to: \(gifURL.lastPathComponent)")

        // 6. Save tensor if present
        if let tensorData = result.tensorData {
            let tensorURL = documentsPath.appendingPathComponent("test_tensor.bin")
            try tensorData.write(to: tensorURL)
            print("✅ Saved tensor (\(tensorData.count) bytes) to: \(tensorURL.lastPathComponent)")
        }

        print("🎉 Pipeline test complete!")
    }

    /// Generate test frames with gradient pattern
    private static func generateTestFrames() -> [Data] {
        var frames: [Data] = []
        let size = 1080
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel

        for frameIndex in 0..<256 {
            var frameData = Data(capacity: size * size * bytesPerPixel)

            // Create gradient that changes per frame
            let hue = CGFloat(frameIndex) / 256.0
            let color = UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)

            let baseR = UInt8(r * 255)
            let baseG = UInt8(g * 255)
            let baseB = UInt8(b * 255)

            for y in 0..<size {
                for x in 0..<size {
                    // Create gradient across image
                    let gradX = CGFloat(x) / CGFloat(size)
                    let gradY = CGFloat(y) / CGFloat(size)

                    frameData.append(UInt8(CGFloat(baseB) * gradX)) // B
                    frameData.append(UInt8(CGFloat(baseG) * gradY)) // G
                    frameData.append(baseR)                         // R
                    frameData.append(255)                           // A
                }
            }

            frames.append(frameData)
        }

        return frames
    }

    /// Pack frames into contiguous buffer for FFI
    private static func packFrames(_ frames: [Data]) -> Data {
        var packed = Data(capacity: frames.count * 256 * 256 * 4)
        for frame in frames {
            packed.append(frame)
        }
        return packed
    }
}