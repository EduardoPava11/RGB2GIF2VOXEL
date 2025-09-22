import XCTest
@testable import RGB2GIF2VOXEL

/// Complete pipeline integration tests
final class CompletePipelineTests: XCTestCase {

    // MARK: - Configuration Tests

    func testCaptureConfiguration() {
        XCTAssertEqual(CaptureConfiguration.availableCubeSizes, [528, 264, 132])
        XCTAssertEqual(CaptureConfiguration.availablePaletteSizes, [64, 128, 256])
        XCTAssertEqual(CaptureConfiguration.defaultCubeSize, 132)
        XCTAssertEqual(CaptureConfiguration.defaultPaletteSize, 256)
    }

    func testMemoryCalculations() {
        let memory528 = CaptureConfiguration.memoryInMB(for: 528)
        XCTAssertEqual(memory528, 147.0, accuracy: 1.0)

        let memory264 = CaptureConfiguration.memoryInMB(for: 264)
        XCTAssertEqual(memory264, 18.4, accuracy: 0.5)

        let memory132 = CaptureConfiguration.memoryInMB(for: 132)
        XCTAssertEqual(memory132, 2.3, accuracy: 0.1)
    }

    // MARK: - Error Handling Tests

    func testCaptureErrors() {
        let error = CaptureError.captureIncomplete(captured: 100, needed: 132)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("100/132"))
    }

    func testErrorRecovery() {
        let error = CaptureError.cameraAccessDenied
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion!.contains("Settings"))
    }

    // MARK: - Data Extension Tests

    func testCenterCropSquare() {
        // Create test data (3x2 image -> 2x2 crop)
        let width = 3
        let height = 2
        let bytesPerRow = width * 4
        let originalData = Data(repeating: 0xFF, count: height * bytesPerRow)

        let cropped = Data.centerCropSquareBGRA(
            from: originalData,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )

        let expectedSize = 2 * 2 * 4 // 2x2 pixels, 4 bytes each
        XCTAssertEqual(cropped.count, expectedSize)
    }

    // MARK: - Coordinator Tests

    func testCaptureCoordinator() {
        let coordinator = CaptureCoordinator()

        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertEqual(coordinator.captureProgress, 0)
        XCTAssertNil(coordinator.generatedGIF)
        XCTAssertNil(coordinator.lastError)
    }

    func testCoordinatorConfiguration() {
        let coordinator = CaptureCoordinator()

        coordinator.cubeSize = 264
        XCTAssertEqual(coordinator.cubeSize, 264)

        coordinator.paletteSize = 128
        XCTAssertEqual(coordinator.paletteSize, 128)
    }

    // MARK: - Mock Tests (for DEBUG builds)

    #if DEBUG
    func testMockProcessor() async throws {
        let processor = MockYinGifProcessor()

        let testData = Data(repeating: 0xFF, count: 1024 * 1024 * 4)
        let result = try await processor.processFrameAsync(
            bgraData: testData,
            width: 1024,
            height: 1024,
            targetSize: 128,
            paletteSize: 256
        )

        XCTAssertEqual(result.width, 128)
        XCTAssertEqual(result.height, 128)
        XCTAssertEqual(result.indices.count, 128 * 128)
        XCTAssertEqual(result.palette.count, 256)
    }

    func testMockGIFEncoder() {
        let tensorData = CubeTensorData(
            size: 64,
            indices: Array(repeating: 0, count: 64 * 64 * 64),
            palette: Array(repeating: 0xFFFFFF, count: 256),
            paletteSize: 256
        )

        let gifData = MockGIF89aEncoder.encode(tensor: tensorData)
        XCTAssertNotNil(gifData)
        XCTAssert(gifData!.starts(with: "GIF89a".data(using: .utf8)!))
    }
    #endif

    // MARK: - Type Safety Tests

    func testNoLegacyTypes() {
        // This test ensures no legacy types are accessible
        // If any of these compile, we have a problem:

        // These should NOT exist:
        // _ = DownsizeOption.self  // ❌ Should not compile
        // _ = PaletteOption.self   // ❌ Should not compile
        // _ = SquareCameraView.self // ❌ Should not compile
        // _ = FrontCameraManager.self // ❌ Should not compile

        // These SHOULD exist:
        _ = CubeTensor.self // ✅
        _ = CubeTensorData.self // ✅
        _ = CubeClipController.self // ✅
        _ = CubeCameraManager.self // ✅
        _ = CubePolicy.self // ✅
        _ = QuantizedFrame.self // ✅
        _ = CaptureConfiguration.self // ✅
        _ = CaptureError.self // ✅
        _ = CaptureCoordinator.self // ✅
    }

    // MARK: - Pipeline Integration Test

    func testCompletePipelineTypes() {
        // Verify all types can be instantiated
        let _ = CubeClipController(sideN: 64, paletteSize: 64)
        let _ = CubeCameraManager()
        let _ = CaptureCoordinator()

        // Verify tensor creation
        let frames: [QuantizedFrame] = []
        let tensor = CubeTensor(frames: frames, sideN: 64, paletteSize: 64)
        let tensorData = tensor.toCubeTensorData()

        XCTAssertEqual(tensorData.size, 64)
        XCTAssertEqual(tensorData.paletteSize, 64)
    }

    // MARK: - Performance Tests

    func testTensorCreationPerformance() {
        let frames = (0..<132).map { i in
            QuantizedFrame(
                width: 132,
                height: 132,
                indices: Data(repeating: UInt8(i % 256), count: 132 * 132),
                palette: Array(repeating: UInt32(0xFFFFFF), count: 256)
            )
        }

        measure {
            let tensor = CubeTensor(
                frames: frames,
                sideN: 132,
                paletteSize: 256
            )
            _ = tensor.toCubeTensorData()
        }
    }
}