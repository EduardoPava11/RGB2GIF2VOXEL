//
//  FrameProcessingTests.swift
//  RGB2GIF2VOXELTests
//
//  Tests for frame processing pipeline and tensor construction
//

import XCTest
import CoreVideo
@testable import RGB2GIF2VOXEL

final class FrameProcessingTests: XCTestCase {

    var frameProcessor: FrameProcessor!
    var testFrames: [CVPixelBuffer] = []

    override func setUp() {
        super.setUp()
        frameProcessor = FrameProcessor()

        // Create test frames
        for i in 0..<10 {
            let buffer = createTestFrame(index: i)
            testFrames.append(buffer)
        }
    }

    override func tearDown() {
        frameProcessor = nil
        testFrames = []
        super.tearDown()
    }

    // MARK: - Frame Processing Tests

    func testProcessSingleFrame() {
        // Given
        let frame = testFrames[0]

        // When
        let result = frameProcessor.processFrame(frame)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 256)
        XCTAssertEqual(result?.height, 256)
    }

    func testBatchProcessingMaintainsOrder() {
        // Given
        let frames = Array(testFrames.prefix(5))

        // When
        let results = frameProcessor.processBatch(frames)

        // Then
        XCTAssertEqual(results.count, frames.count)
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result.index, index)
        }
    }

    func testParallelProcessingPerformance() {
        // Given
        let frames = testFrames

        // Measure serial processing
        let serialTime = measureTime {
            _ = frames.map { frameProcessor.processFrame($0) }
        }

        // Measure parallel processing
        let parallelTime = measureTime {
            _ = frameProcessor.processParallel(frames)
        }

        // Then - Parallel should be faster
        XCTAssertLessThan(parallelTime, serialTime)
        print("Serial: \(serialTime)s, Parallel: \(parallelTime)s")
    }

    // MARK: - Tensor Construction Tests

    func testBuildCubeTensor() {
        // Given
        let clipController = CubeClipController()
        for frame in testFrames {
            clipController.addFrame(frame)
        }

        // When
        let tensor = clipController.buildCubeTensor()

        // Then
        XCTAssertNotNil(tensor)
        XCTAssertEqual(tensor?.dimensions.count, 3)
        XCTAssertEqual(tensor?.dimensions[0], 256)
        XCTAssertEqual(tensor?.dimensions[1], 256)
    }

    func testTensorMemoryLayout() {
        // Given
        let tensor = CubeTensor(frames: testFrames)

        // When
        let data = tensor.toCubeTensorData()

        // Then
        let expectedSize = 256 * 256 * min(256, testFrames.count) * 4
        XCTAssertEqual(data.data.count, expectedSize)
        XCTAssertEqual(data.size, 256)
    }

    // MARK: - Format Conversion Tests

    func testBGRAToRGBAConversion() {
        // Given
        let bgraBuffer = createBGRABuffer()

        // When
        let rgbaData = frameProcessor.convertBGRAToRGBA(bgraBuffer)

        // Then
        XCTAssertNotNil(rgbaData)
        // Verify byte swapping occurred
        XCTAssertEqual(rgbaData[0], bgraBuffer[2]) // R
        XCTAssertEqual(rgbaData[1], bgraBuffer[1]) // G
        XCTAssertEqual(rgbaData[2], bgraBuffer[0]) // B
        XCTAssertEqual(rgbaData[3], bgraBuffer[3]) // A
    }

    // MARK: - Memory Management Tests

    func testMemoryPoolReuse() {
        // Given
        let pool = frameProcessor.bufferPool
        let initialBuffer = pool.acquire()
        let initialAddress = initialBuffer.baseAddress

        // When
        pool.release(initialBuffer)
        let reusedBuffer = pool.acquire()

        // Then - Should get same buffer back
        XCTAssertEqual(reusedBuffer.baseAddress, initialAddress)
    }

    func testMemoryPressureHandling() {
        // Given
        var buffers: [CVPixelBuffer] = []

        // When - Allocate many buffers
        for _ in 0..<100 {
            let buffer = createLargeTestFrame()
            buffers.append(buffer)
        }

        // Then - Should handle memory pressure
        let memoryUsed = getMemoryUsage()
        XCTAssertLessThan(memoryUsed, 500_000_000) // Less than 500MB
    }

    // MARK: - Error Handling Tests

    func testInvalidFrameHandling() {
        // Given
        let invalidBuffer = createInvalidBuffer()

        // When
        let result = frameProcessor.processFrame(invalidBuffer)

        // Then
        XCTAssertNil(result)
    }

    func testPartialBatchProcessing() {
        // Given
        var frames = testFrames
        frames[5] = createInvalidBuffer() // Insert invalid frame

        // When
        let results = frameProcessor.processBatch(frames, skipInvalid: true)

        // Then
        XCTAssertEqual(results.count, frames.count - 1) // Should skip invalid
    }

    // MARK: - Performance Benchmarks

    func testSingleFrameProcessingPerformance() {
        let frame = createTestFrame(index: 0)

        measure {
            _ = frameProcessor.processFrame(frame)
        }
    }

    func test256FrameProcessingPerformance() {
        let frames = (0..<256).map { createTestFrame(index: $0) }

        measure {
            _ = frameProcessor.processBatch(frames)
        }
    }

    // MARK: - Helper Methods

    private func createTestFrame(index: Int) -> CVPixelBuffer {
        return TestUtilities.createPixelBuffer(
            width: 1920,
            height: 1080,
            format: kCVPixelFormatType_32BGRA
        )
    }

    private func createLargeTestFrame() -> CVPixelBuffer {
        return TestUtilities.createPixelBuffer(
            width: 4096,
            height: 2160,
            format: kCVPixelFormatType_32BGRA
        )
    }

    private func createInvalidBuffer() -> CVPixelBuffer {
        // Create buffer with invalid format
        return TestUtilities.createPixelBuffer(
            width: 100,
            height: 100,
            format: kCVPixelFormatType_422YpCbCr8
        )
    }

    private func createBGRABuffer() -> Data {
        return Data([100, 150, 200, 255]) // BGRA values
    }

    private func measureTime(block: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Test Utilities

enum TestUtilities {
    static func createPixelBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            attributes,
            &pixelBuffer
        )

        return pixelBuffer!
    }
}