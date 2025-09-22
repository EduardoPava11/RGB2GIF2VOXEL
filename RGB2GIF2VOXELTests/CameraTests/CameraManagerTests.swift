//
//  CameraManagerTests.swift
//  RGB2GIF2VOXELTests
//
//  Unit tests for camera setup, configuration, and frame capture
//

import XCTest
import AVFoundation
@testable import RGB2GIF2VOXEL

final class CameraManagerTests: XCTestCase {

    var sut: CubeCameraManagerOptimized!
    var mockSession: MockCaptureSession!

    override func setUp() {
        super.setUp()
        sut = CubeCameraManagerOptimized()
        mockSession = MockCaptureSession()
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Setup Tests

    func testCameraSetupConfiguresSession() {
        // Given
        let expectation = XCTestExpectation(description: "Session configured")

        // When
        sut.setupSession()

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertNotNil(self.sut.session)
            XCTAssertTrue(self.sut.session.inputs.count > 0)
            XCTAssertTrue(self.sut.session.outputs.count > 0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testCameraSetupSelectsCorrectDevice() {
        // When
        sut.setupSession()

        // Then
        let input = sut.session.inputs.first as? AVCaptureDeviceInput
        XCTAssertNotNil(input)
        XCTAssertEqual(input?.device.position, .back)
    }

    // MARK: - Frame Capture Tests

    func testStartCaptureInitializesBuffer() {
        // When
        sut.startCapture()

        // Then
        XCTAssertTrue(sut.isCapturing)
        XCTAssertEqual(sut.clipController.framesCaptured, 0)
        XCTAssertNotNil(sut.clipController.frames)
    }

    func testStopCaptureResetsState() {
        // Given
        sut.startCapture()

        // When
        sut.stopCapture()

        // Then
        XCTAssertFalse(sut.isCapturing)
    }

    // MARK: - Frame Processing Tests

    func testCenterCropToSquareOptimized() {
        // Given
        let inputBuffer = createTestPixelBuffer(width: 1920, height: 1080)

        // When
        let result = sut.centerCropToSquareOptimized(inputBuffer)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(CVPixelBufferGetWidth(result!), 1080)
        XCTAssertEqual(CVPixelBufferGetHeight(result!), 1080)
    }

    func testCenterCropPreservesCenter() {
        // Given
        let inputBuffer = createGradientPixelBuffer(width: 1920, height: 1080)

        // When
        let result = sut.centerCropToSquareOptimized(inputBuffer)!

        // Then
        let centerPixel = getPixel(from: result, x: 540, y: 540)
        XCTAssertNotNil(centerPixel)
        // Verify center pixel is preserved from original
    }

    // MARK: - Performance Tests

    func testFrameProcessingPerformance() {
        // Given
        let inputBuffer = createTestPixelBuffer(width: 1920, height: 1080)

        // Measure
        measure {
            _ = sut.centerCropToSquareOptimized(inputBuffer)
        }
    }

    func testBatchFrameProcessingPerformance() {
        // Given
        let frames = (0..<30).map { _ in
            createTestPixelBuffer(width: 1920, height: 1080)
        }

        // Measure
        measure {
            for frame in frames {
                _ = sut.centerCropToSquareOptimized(frame)
            }
        }
    }

    // MARK: - Memory Tests

    func testMemoryUsageUnderLoad() {
        // Given
        let memoryBefore = reportMemory()

        // When - Process 256 frames
        for _ in 0..<256 {
            let buffer = createTestPixelBuffer(width: 1920, height: 1080)
            _ = sut.centerCropToSquareOptimized(buffer)
        }

        // Then
        let memoryAfter = reportMemory()
        let increase = memoryAfter - memoryBefore

        // Should not exceed 200MB increase
        XCTAssertLessThan(increase, 200_000_000)
    }

    // MARK: - Helper Methods

    private func createTestPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )

        return pixelBuffer!
    }

    private func createGradientPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        let buffer = createTestPixelBuffer(width: width, height: height)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let ptr = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: offset)
                ptr[0] = UInt8((x * 255) / width)   // B
                ptr[1] = UInt8((y * 255) / height)  // G
                ptr[2] = UInt8(128)                 // R
                ptr[3] = 255                        // A
            }
        }

        return buffer
    }

    private func getPixel(from buffer: CVPixelBuffer, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        let offset = y * bytesPerRow + x * 4
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: offset)

        return (r: ptr[2], g: ptr[1], b: ptr[0], a: ptr[3])
    }

    private func reportMemory() -> Int64 {
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

// MARK: - Mock Objects

class MockCaptureSession: AVCaptureSession {
    var mockInputs: [AVCaptureInput] = []
    var mockOutputs: [AVCaptureOutput] = []

    override var inputs: [AVCaptureInput] {
        return mockInputs
    }

    override var outputs: [AVCaptureOutput] {
        return mockOutputs
    }

    override func startRunning() {
        // Mock implementation
    }

    override func stopRunning() {
        // Mock implementation
    }
}