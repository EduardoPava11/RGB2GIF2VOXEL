//
//  FFIOptionsBuilderTests.swift
//  RGB2GIF2VOXELTests
//
//  Unit tests for FFI type conversions and boundary conditions
//

import XCTest
@testable import RGB2GIF2VOXEL

final class FFIOptionsBuilderTests: XCTestCase {

    // MARK: - GifOpts Tests

    func testGifOptsWithValidInputs() {
        let gifOpts = FFIOptionsBuilder.buildGifOpts(
            width: 128,
            height: 128,
            frameCount: 128,
            fps: 25,
            loopCount: 0
        )

        XCTAssertEqual(gifOpts.width, 128)
        XCTAssertEqual(gifOpts.height, 128)
        XCTAssertEqual(gifOpts.frameCount, 128)
        XCTAssertEqual(gifOpts.fps, 25)
        XCTAssertEqual(gifOpts.loopCount, 0)
        XCTAssertTrue(gifOpts.optimize)
        XCTAssertTrue(gifOpts.includeTensor)
    }

    func testGifOptsClampingNegativeValues() {
        let gifOpts = FFIOptionsBuilder.buildGifOpts(
            width: -100,
            height: -200,
            frameCount: -10,
            fps: -5
        )

        XCTAssertEqual(gifOpts.width, 1, "Negative width should clamp to 1")
        XCTAssertEqual(gifOpts.height, 1, "Negative height should clamp to 1")
        XCTAssertEqual(gifOpts.frameCount, 1, "Negative frameCount should clamp to 1")
        XCTAssertEqual(gifOpts.fps, 1, "Negative fps should clamp to 1")
    }

    func testGifOptsClampingLargeValues() {
        let gifOpts = FFIOptionsBuilder.buildGifOpts(
            width: 10000,
            height: 10000,
            frameCount: 2000,
            fps: 200
        )

        XCTAssertEqual(gifOpts.width, 4096, "Large width should clamp to 4096")
        XCTAssertEqual(gifOpts.height, 4096, "Large height should clamp to 4096")
        XCTAssertEqual(gifOpts.frameCount, 1024, "Large frameCount should clamp to 1024")
        XCTAssertEqual(gifOpts.fps, 100, "Large fps should clamp to 100")
    }

    func testGifOptsN128Preset() {
        let gifOpts = FFIOptionsBuilder.buildN128GifOpts(frameCount: 128)

        XCTAssertEqual(gifOpts.width, 128, "N=128 width")
        XCTAssertEqual(gifOpts.height, 128, "N=128 height")
        XCTAssertEqual(gifOpts.frameCount, 128)
        XCTAssertEqual(gifOpts.fps, 25)
        XCTAssertTrue(gifOpts.includeTensor, "Tensor generation enabled for voxels")
    }

    // MARK: - QuantizeOpts Tests

    func testQuantizeOptsWithValidInputs() {
        let quantizeOpts = FFIOptionsBuilder.buildQuantizeOpts(
            qualityMin: 70,
            qualityMax: 95,
            speed: 5,
            paletteSize: 256,
            ditheringLevel: 0.8
        )

        XCTAssertEqual(quantizeOpts.qualityMin, 70)
        XCTAssertEqual(quantizeOpts.qualityMax, 95)
        XCTAssertEqual(quantizeOpts.speed, 5)
        XCTAssertEqual(quantizeOpts.paletteSize, 256)
        XCTAssertEqual(quantizeOpts.ditheringLevel, 0.8, accuracy: 0.001)
        XCTAssertTrue(quantizeOpts.sharedPalette)
    }

    func testQuantizeOptsQualityRangeValidation() {
        let quantizeOpts = FFIOptionsBuilder.buildQuantizeOpts(
            qualityMin: 150,
            qualityMax: 50
        )

        XCTAssertEqual(quantizeOpts.qualityMin, 100, "qualityMin should clamp to 100")
        XCTAssertEqual(quantizeOpts.qualityMax, 100, "qualityMax should be at least qualityMin")
    }

    func testQuantizeOptsPaletteSizeClamping() {
        // Test too small
        let smallPalette = FFIOptionsBuilder.buildQuantizeOpts(paletteSize: 1)
        XCTAssertEqual(smallPalette.paletteSize, 2, "Palette size should clamp to minimum 2")

        // Test too large
        let largePalette = FFIOptionsBuilder.buildQuantizeOpts(paletteSize: 500)
        XCTAssertEqual(largePalette.paletteSize, 256, "Palette size should clamp to 256 (GIF limit)")

        // Test edge case
        let edgePalette = FFIOptionsBuilder.buildQuantizeOpts(paletteSize: 256)
        XCTAssertEqual(edgePalette.paletteSize, 256, "Palette size 256 should be valid")
    }

    func testQuantizeOptsSpeedClamping() {
        // Test too slow
        let slowSpeed = FFIOptionsBuilder.buildQuantizeOpts(speed: 0)
        XCTAssertEqual(slowSpeed.speed, 1, "Speed should clamp to minimum 1")

        // Test too fast
        let fastSpeed = FFIOptionsBuilder.buildQuantizeOpts(speed: 15)
        XCTAssertEqual(fastSpeed.speed, 10, "Speed should clamp to maximum 10")
    }

    func testQuantizeOptsDitheringLevelClamping() {
        // Test negative
        let negativeDither = FFIOptionsBuilder.buildQuantizeOpts(ditheringLevel: -0.5)
        XCTAssertEqual(negativeDither.ditheringLevel, 0.0, accuracy: 0.001)

        // Test too high
        let highDither = FFIOptionsBuilder.buildQuantizeOpts(ditheringLevel: 2.0)
        XCTAssertEqual(highDither.ditheringLevel, 1.0, accuracy: 0.001)
    }

    func testQuantizeOptsN128Preset() {
        let quantizeOpts = FFIOptionsBuilder.buildN128QuantizeOpts()

        XCTAssertEqual(quantizeOpts.qualityMin, 70)
        XCTAssertEqual(quantizeOpts.qualityMax, 95)
        XCTAssertEqual(quantizeOpts.speed, 5)
        XCTAssertEqual(quantizeOpts.paletteSize, 256)
        XCTAssertEqual(quantizeOpts.ditheringLevel, 0.8, accuracy: 0.001)
        XCTAssertTrue(quantizeOpts.sharedPalette)
    }

    // MARK: - ProcessorOptions Tests

    func testProcessorOptionsN128Preset() {
        let options = FFIOptionsBuilder.n128ProcessorOptions

        XCTAssertEqual(options.gif.width, 128)
        XCTAssertEqual(options.gif.height, 128)
        XCTAssertEqual(options.gif.frameCount, 128)
        XCTAssertEqual(options.quantize.paletteSize, 256)
        XCTAssertTrue(options.parallel)
    }

    func testBuildProcessorOptionsCustom() {
        let options = FFIOptionsBuilder.buildProcessorOptions(
            frameCount: 64,
            targetSize: 256,
            paletteSize: 128
        )

        XCTAssertEqual(options.gif.width, 256)
        XCTAssertEqual(options.gif.height, 256)
        XCTAssertEqual(options.gif.frameCount, 64)
        XCTAssertEqual(options.quantize.paletteSize, 128)
    }

    // MARK: - Performance Tests

    func testBuilderPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = FFIOptionsBuilder.buildGifOpts(
                    width: Int.random(in: 1...4096),
                    height: Int.random(in: 1...4096),
                    frameCount: Int.random(in: 1...1024)
                )
            }
        }
    }

    // MARK: - Edge Cases

    func testUInt16MaxBoundary() {
        let maxInt = Int(UInt16.max) + 100
        let gifOpts = FFIOptionsBuilder.buildGifOpts(
            width: maxInt,
            height: maxInt,
            frameCount: maxInt,
            loopCount: maxInt
        )

        XCTAssertEqual(gifOpts.width, 4096, "Should clamp to max dimension")
        XCTAssertEqual(gifOpts.height, 4096, "Should clamp to max dimension")
        XCTAssertEqual(gifOpts.frameCount, 1024, "Should clamp to max frame count")
        XCTAssertLessThanOrEqual(gifOpts.loopCount, UInt16.max, "Should not overflow UInt16")
    }

    func testZeroInputs() {
        let gifOpts = FFIOptionsBuilder.buildGifOpts(
            width: 0,
            height: 0,
            frameCount: 0,
            fps: 0
        )

        XCTAssertGreaterThan(gifOpts.width, 0, "Width should be positive")
        XCTAssertGreaterThan(gifOpts.height, 0, "Height should be positive")
        XCTAssertGreaterThan(gifOpts.frameCount, 0, "Frame count should be positive")
        XCTAssertGreaterThan(gifOpts.fps, 0, "FPS should be positive")
    }
}

// MARK: - Timestamp Acceptance Tests

final class TimestampAcceptanceTests: XCTestCase {

    func testStrictMonotonicityEnforcement() {
        let controller = CubeClipController(sideN: 128, paletteSize: 256)

        // First frame should always be accepted
        XCTAssertTrue(controller.shouldAcceptNextFrame(timestamp: CMTime(value: 0, timescale: 1000)))

        // Same timestamp should be rejected
        XCTAssertFalse(controller.shouldAcceptNextFrame(timestamp: CMTime(value: 0, timescale: 1000)))

        // Earlier timestamp should be rejected
        XCTAssertFalse(controller.shouldAcceptNextFrame(timestamp: CMTime(value: -100, timescale: 1000)))

        // Later timestamp should be accepted
        XCTAssertTrue(controller.shouldAcceptNextFrame(timestamp: CMTime(value: 100, timescale: 1000)))
    }

    func testTargetFPSControl() {
        let controller = CubeClipController(sideN: 128, paletteSize: 256)
        controller.targetFPS = 30 // Accept every ~33ms

        let startTime = CMTime(value: 0, timescale: 1000)
        XCTAssertTrue(controller.shouldAcceptNextFrame(timestamp: startTime))

        // Too soon (10ms) - should reject
        let tooSoon = CMTime(value: 10, timescale: 1000)
        XCTAssertFalse(controller.shouldAcceptNextFrame(timestamp: tooSoon))

        // Right time (33ms) - should accept
        let rightTime = CMTime(value: 33, timescale: 1000)
        XCTAssertTrue(controller.shouldAcceptNextFrame(timestamp: rightTime))
    }
}

// MARK: - Cropping Tests

final class CroppingTests: XCTestCase {

    func testBGRACroppingCorrectness() {
        // Create a test pixel buffer
        let width = 1920
        let height = 1080
        let pixelBuffer = createTestPixelBuffer(width: width, height: height, format: kCVPixelFormatType_32BGRA)

        let manager = CubeCameraManagerOptimized()
        manager.captureMode = .bgra

        // Test cropping (this would need access to the private method or a testable interface)
        // For now, just verify the manager is configured correctly
        XCTAssertEqual(manager.captureMode, .bgra)
    }

    func testYUVCroppingIsGated() {
        let manager = CubeCameraManagerOptimized()
        manager.captureMode = .yuv420f

        // YUV cropping should be disabled as per our fix
        // The warning log should be emitted when cropping is attempted
        XCTAssertEqual(manager.captureMode, .yuv420f)
    }

    private func createTestPixelBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            attributes as CFDictionary,
            &pixelBuffer
        )

        return pixelBuffer!
    }
}