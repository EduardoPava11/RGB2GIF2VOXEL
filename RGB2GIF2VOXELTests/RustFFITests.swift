//
//  RustFFITests.swift
//  RGB2GIF2VOXELTests
//
//  Tests that verify the Rust FFI bridge works correctly
//

import XCTest
@testable import RGB2GIF2VOXEL

final class RustFFITests: XCTestCase {

    // MARK: - Test Setup

    override func setUpWithError() throws {
        super.setUp()
        print("🧪 Starting Rust FFI test...")
    }

    override func tearDownWithError() throws {
        print("✅ Test complete\n")
        super.tearDown()
    }

    // MARK: - Basic FFI Tests

    func testProcessorCreation() throws {
        print("Testing processor creation...")

        let processor = yingif_processor_new()
        XCTAssertNotNil(processor, "Failed to create processor")

        yingif_processor_free(processor)
        print("  ✅ Processor created and freed successfully")
    }

    func testGifSizeEstimation() throws {
        print("Testing GIF size estimation...")

        let estimated = yingif_estimate_gif_size(32, 256)
        XCTAssertGreaterThan(estimated, 0, "Size estimation returned 0")
        XCTAssertLessThan(estimated, 100_000_000, "Size unreasonably large")

        print("  Estimated size for 32×32×32: \(estimated) bytes")
        print("  ✅ Size estimation works")
    }

    // MARK: - Frame Processing Tests

    func testSimpleFrameProcessing() throws {
        print("Testing simple frame processing...")

        let processor = yingif_processor_new()
        XCTAssertNotNil(processor)

        // Create 4×4 test frame in BGRA format
        var testFrame = Data(count: 64)
        for i in 0..<64 {
            testFrame[i] = UInt8(i)
        }

        var indices = [UInt8](repeating: 0, count: 4) // 2×2 output
        var palette = [UInt32](repeating: 0, count: 16)

        let result = testFrame.withUnsafeBytes { bytes in
            yingif_process_frame(
                processor,
                bytes.baseAddress,
                4, 4,  // Input size
                2,     // Target size
                16,    // Palette size
                &indices,
                &palette
            )
        }

        XCTAssertEqual(result, 0, "Processing failed with error: \(result)")

        yingif_processor_free(processor)
        print("  ✅ Simple frame processing works")
    }

    func testHDTo256Processing() throws {
        print("Testing HD (1080×1080) → 256×256 processing...")

        let processor = yingif_processor_new()
        XCTAssertNotNil(processor)

        // Generate HD test frame in BGRA format
        let width = 1080
        let height = 1080
        var bgraFrame = Data(count: width * height * 4)

        bgraFrame.withUnsafeMutableBytes { bytes in
            guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    ptr[offset] = UInt8((x * 255) / width)     // B
                    ptr[offset + 1] = UInt8((y * 255) / height) // G
                    ptr[offset + 2] = 128                       // R
                    ptr[offset + 3] = 255                       // A
                }
            }
        }

        var indices = [UInt8](repeating: 0, count: 256 * 256)
        var palette = [UInt32](repeating: 0, count: 256)

        let result = bgraFrame.withUnsafeBytes { bytes in
            yingif_process_frame(
                processor,
                bytes.baseAddress,
                Int32(width), Int32(height),
                256,  // Target 256×256
                256,  // 256 colors
                &indices,
                &palette
            )
        }

        XCTAssertEqual(result, 0, "HD processing failed")

        // Verify output quality
        let nonZeroIndices = indices.filter { $0 != 0 }.count
        XCTAssertGreaterThan(nonZeroIndices, 1000, "Too few non-zero indices")

        let validColors = palette.filter { $0 != 0 && $0 != 0xFF000000 }.count
        XCTAssertGreaterThan(validColors, 10, "Too few unique colors")

        yingif_processor_free(processor)
        print("  Non-zero indices: \(nonZeroIndices)")
        print("  Unique colors: \(validColors)")
        print("  ✅ HD processing works")
    }

    // MARK: - Batch Processing Tests

    func testBatchProcessing() throws {
        print("Testing batch processing (yx_proc_batch_rgba8)...")

        let frameCount = 4
        let width = 512
        let height = 512
        let targetSide = 128
        let paletteSize = 256

        // Generate test frames
        var frames: [[UInt8]] = []
        for i in 0..<frameCount {
            var frame = [UInt8](repeating: 0, count: width * height * 4)
            for j in 0..<frame.count {
                frame[j] = UInt8((j + i * 10) % 256)
            }
            frames.append(frame)
        }

        // Create frame pointers
        var framePointers: [UnsafePointer<UInt8>?] = frames.map { frame in
            frame.withUnsafeBufferPointer { $0.baseAddress }
        }

        var indices = [UInt8](repeating: 0, count: targetSide * targetSide * frameCount)
        var palettes = [UInt32](repeating: 0, count: paletteSize * frameCount)

        let result = framePointers.withUnsafeMutableBufferPointer { pointers in
            yx_proc_batch_rgba8(
                pointers.baseAddress,
                Int32(frameCount),
                Int32(width),
                Int32(height),
                Int32(targetSide),
                Int32(paletteSize),
                &indices,
                &palettes
            )
        }

        XCTAssertEqual(result, 0, "Batch processing failed")

        // Verify each frame was processed
        for i in 0..<frameCount {
            let frameStart = i * targetSide * targetSide
            let frameEnd = frameStart + targetSide * targetSide
            let frameIndices = Array(indices[frameStart..<frameEnd])

            let nonZero = frameIndices.filter { $0 != 0 }.count
            XCTAssertGreaterThan(nonZero, 0, "Frame \(i) has no data")
        }

        print("  Processed \(frameCount) frames")
        print("  ✅ Batch processing works")
    }

    // MARK: - GIF Creation Tests

    func testGifCreation() throws {
        print("Testing GIF creation...")

        let cubeSize: Int32 = 4
        let paletteSize: Int32 = 16

        // Create test data
        var indices = [UInt8](repeating: 0, count: Int(cubeSize * cubeSize * cubeSize))
        for i in 0..<indices.count {
            indices[i] = UInt8(i % Int(paletteSize))
        }

        var palette = [UInt32](repeating: 0, count: Int(paletteSize))
        for i in 0..<Int(paletteSize) {
            let gray = UInt32(i * 255 / Int(paletteSize))
            palette[i] = 0xFF000000 | (gray << 16) | (gray << 8) | gray
        }

        // Estimate size
        let estimated = yingif_estimate_gif_size(cubeSize, paletteSize)
        XCTAssertGreaterThan(estimated, 0)

        // Create GIF
        var gifData = [UInt8](repeating: 0, count: Int(estimated * 2))
        var actualSize: Int32 = 0

        let result = yingif_create_gif89a(
            indices,
            palette,
            cubeSize,
            paletteSize,
            40, // 40ms delay
            &gifData,
            Int32(gifData.count),
            &actualSize
        )

        XCTAssertEqual(result, 0, "GIF creation failed")
        XCTAssertGreaterThan(actualSize, 0, "GIF has zero size")

        // Verify GIF header
        let header = String(bytes: gifData[0..<6], encoding: .ascii)
        XCTAssertEqual(header, "GIF89a", "Invalid GIF header")

        print("  GIF size: \(actualSize) bytes")
        print("  ✅ GIF creation works")
    }

    // MARK: - Memory & Performance Tests

    func test256CubeMemoryRequirements() throws {
        print("Testing 256×256×256 memory calculations...")

        let cubeSize = 256
        let framePixels = cubeSize * cubeSize
        let totalPixels = framePixels * cubeSize

        // Calculate requirements
        let indicesSize = totalPixels * MemoryLayout<UInt8>.size
        let paletteSize = cubeSize * 256 * MemoryLayout<UInt32>.size
        let estimatedGif = Int(yingif_estimate_gif_size(Int32(cubeSize), 256))

        print("  256³ cube memory:")
        print("    Indices: \(indicesSize / 1024 / 1024) MB")
        print("    Palettes: \(paletteSize / 1024) KB")
        print("    Est. GIF: \(estimatedGif / 1024 / 1024) MB")
        print("    Total: ~\((indicesSize + paletteSize + estimatedGif) / 1024 / 1024) MB")

        XCTAssertEqual(indicesSize, 16_777_216, "Incorrect indices size")
        XCTAssertLessThan(estimatedGif, 100_000_000, "GIF too large")

        print("  ✅ Memory calculations correct")
    }

    func testPerformance256Processing() throws {
        print("Testing performance with 256×256 frames...")

        let processor = yingif_processor_new()
        XCTAssertNotNil(processor)

        // Generate test frame
        let size = 1080
        var frame = Data(count: size * size * 4)
        for i in 0..<frame.count {
            frame[i] = UInt8(i % 256)
        }

        var indices = [UInt8](repeating: 0, count: 256 * 256)
        var palette = [UInt32](repeating: 0, count: 256)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Process 10 frames
        for _ in 0..<10 {
            let result = frame.withUnsafeBytes { bytes in
                yingif_process_frame(
                    processor,
                    bytes.baseAddress,
                    Int32(size), Int32(size),
                    256, 256,
                    &indices,
                    &palette
                )
            }
            XCTAssertEqual(result, 0)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let avgTime = elapsed / 10.0

        yingif_processor_free(processor)

        print("  Average processing time: \(String(format: "%.2f", avgTime * 1000))ms per frame")
        print("  Estimated FPS: \(String(format: "%.1f", 1.0 / avgTime))")

        // Should process in reasonable time (< 100ms per frame)
        XCTAssertLessThan(avgTime, 0.1, "Processing too slow")

        print("  ✅ Performance acceptable")
    }

    // MARK: - Integration Test

    func testFullPipeline256Cube() throws {
        print("Testing full 256×256×256 pipeline...")

        let frameCount = 8 // Test with 8 frames (full 256 would be slow)
        let captureSize = 1080
        let targetSize = 256

        // 1. Generate frames
        print("  1. Generating \(frameCount) test frames...")
        var frames: [[UInt8]] = []
        for i in 0..<frameCount {
            var frame = [UInt8](repeating: 0, count: captureSize * captureSize * 4)
            // Create gradient pattern
            for y in 0..<captureSize {
                for x in 0..<captureSize {
                    let offset = (y * captureSize + x) * 4
                    frame[offset] = UInt8((x * 255) / captureSize)     // R
                    frame[offset + 1] = UInt8((y * 255) / captureSize) // G
                    frame[offset + 2] = UInt8((i * 255) / frameCount)  // B
                    frame[offset + 3] = 255                            // A
                }
            }
            frames.append(frame)
        }

        // 2. Batch process frames
        print("  2. Batch processing to 256×256...")
        var framePointers = frames.map { frame in
            frame.withUnsafeBufferPointer { $0.baseAddress }
        }

        var indices = [UInt8](repeating: 0, count: targetSize * targetSize * frameCount)
        var palettes = [UInt32](repeating: 0, count: 256 * frameCount)

        let processResult = framePointers.withUnsafeMutableBufferPointer { pointers in
            yx_proc_batch_rgba8(
                pointers.baseAddress,
                Int32(frameCount),
                Int32(captureSize),
                Int32(captureSize),
                Int32(targetSize),
                256,
                &indices,
                &palettes
            )
        }

        XCTAssertEqual(processResult, 0, "Batch processing failed")

        // 3. Create GIF
        print("  3. Encoding to GIF89a...")
        let gifBufferSize = 10_000_000 // 10MB buffer
        var gifData = [UInt8](repeating: 0, count: gifBufferSize)
        var gifSize = 0

        let encodeResult = yx_gif_encode(
            indices,
            palettes,
            Int32(frameCount),
            Int32(targetSize),
            4, // 40ms delay (25 FPS)
            &gifData,
            &gifSize
        )

        XCTAssertEqual(encodeResult, 0, "GIF encoding failed")
        XCTAssertGreaterThan(gifSize, 0, "GIF has zero size")

        // 4. Verify output
        print("  4. Verifying output...")
        let gifBytes = Array(gifData[0..<gifSize])
        let gifHeader = String(bytes: gifBytes[0..<6], encoding: .ascii)
        XCTAssertEqual(gifHeader, "GIF89a", "Invalid GIF header")

        print("  Output:")
        print("    Frames: \(frameCount)")
        print("    Resolution: \(targetSize)×\(targetSize)")
        print("    GIF size: \(gifSize / 1024) KB")

        // Estimate full 256 cube
        let estimated256 = gifSize * (256 / frameCount)
        print("    Estimated for 256 frames: \(estimated256 / 1024 / 1024) MB")

        print("  ✅ Full pipeline works!")
    }
}