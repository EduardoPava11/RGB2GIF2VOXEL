import XCTest
@testable import RGB2GIF2VOXEL

/// Comprehensive test suite for the Cube stack pipeline
/// Ensures contracts are maintained and prevents regressions
final class CubeStackTests: XCTestCase {

    // MARK: - CubePolicy Tests

    func testCubePolicyDefaults() {
        XCTAssertEqual(CubePolicy.defaultLevel, 132)
        XCTAssertEqual(CubePolicy.maxFrames, 528)
        XCTAssertEqual(CubePolicy.defaultPaletteSize, 256)
    }

    func testCubePolicyLevels() {
        let levels = CubePolicy.availableLevels
        XCTAssertEqual(levels, [528, 264, 132])
        XCTAssertTrue(levels.allSatisfy { $0 > 0 && $0 <= 528 })
    }

    // MARK: - CubeTensor Tests

    func testCubeTensorCreation() {
        let frames = createMockFrames(count: 8, size: 8)
        let tensor = CubeTensor(
            frames: frames,
            sideN: 8,
            paletteSize: 256
        )

        XCTAssertEqual(tensor.sideN, 8)
        XCTAssertEqual(tensor.voxelCount, 512) // 8³
        XCTAssertEqual(tensor.frames.count, 8)
    }

    func testCubeTensorFlatIndices() {
        let frames = createMockFrames(count: 4, size: 4)
        let tensor = CubeTensor(
            frames: frames,
            sideN: 4,
            paletteSize: 16
        )

        let flat = tensor.flatIndices()
        XCTAssertEqual(flat.count, 64) // 4³ bytes
    }

    func testCubeTensorToCubeTensorData() {
        let frames = createMockFrames(count: 8, size: 8)
        let tensor = CubeTensor(
            frames: frames,
            sideN: 8,
            paletteSize: 256
        )

        let data = tensor.toCubeTensorData()
        XCTAssertEqual(data.size, 8)
        XCTAssertEqual(data.indices.count, 512)
        XCTAssertEqual(data.paletteSize, 256)
    }

    func testCubeTensorDeterministicHash() {
        let frames = createMockFrames(count: 8, size: 8)
        let tensor1 = CubeTensor(
            frames: frames,
            sideN: 8,
            paletteSize: 256
        )
        let tensor2 = CubeTensor(
            frames: frames,
            sideN: 8,
            paletteSize: 256
        )

        XCTAssertEqual(tensor1.deterministicHash(), tensor2.deterministicHash())
    }

    // MARK: - CubeTensorData Tests

    func testCubeTensorDataVoxelCount() {
        let data = CubeTensorData(
            size: 10,
            indices: Array(repeating: 0, count: 1000),
            palette: [],
            paletteSize: 256
        )

        XCTAssertEqual(data.voxelCount, 1000)
    }

    // MARK: - CubeClipController Tests

    func testCubeClipControllerFrameCapture() {
        let controller = CubeClipController(sideN: 8, paletteSize: 64)

        XCTAssertEqual(controller.framesNeeded, 8)
        XCTAssertFalse(controller.captureComplete)
        XCTAssertEqual(controller.captureProgress, 0.0)
    }

    func testCubeClipControllerAcceptFrame() {
        let controller = CubeClipController(sideN: 4, paletteSize: 16)
        controller.startCapture()

        // Should accept first frame immediately
        let time1 = CMTime(seconds: 0.0, preferredTimescale: 600)
        XCTAssertTrue(controller.shouldAcceptNextFrame(timestamp: time1))

        // Should throttle based on frame interval
        let time2 = CMTime(seconds: 0.01, preferredTimescale: 600)
        XCTAssertFalse(controller.shouldAcceptNextFrame(timestamp: time2))

        // Should accept after sufficient time
        let time3 = CMTime(seconds: 0.1, preferredTimescale: 600)
        XCTAssertTrue(controller.shouldAcceptNextFrame(timestamp: time3))
    }

    func testCubeClipControllerIngest() {
        let controller = CubeClipController(sideN: 2, paletteSize: 4)
        controller.startCapture()

        // Ingest frames
        for i in 0..<2 {
            let frame = createMockFrame(index: i, size: 2)
            let isFinal = controller.ingestFrame(frame)
            XCTAssertEqual(isFinal, i == 1)
        }

        XCTAssertTrue(controller.captureComplete)
        XCTAssertEqual(controller.captureProgress, 1.0)
    }

    func testCubeClipControllerBuildTensor() {
        let controller = CubeClipController(sideN: 2, paletteSize: 4)
        controller.startCapture()

        // No tensor before capture
        XCTAssertNil(controller.buildCubeTensor())

        // Ingest all frames
        for i in 0..<2 {
            let frame = createMockFrame(index: i, size: 2)
            _ = controller.ingestFrame(frame)
        }

        // Should build tensor
        let tensor = controller.buildCubeTensor()
        XCTAssertNotNil(tensor)
        XCTAssertEqual(tensor?.sideN, 2)
        XCTAssertEqual(tensor?.voxelCount, 8)
    }

    // MARK: - Integration Tests

    func testFullPipelineIntegration() {
        // Create controller
        let controller = CubeClipController(sideN: 4, paletteSize: 16)

        // Start capture
        controller.startCapture()
        XCTAssertTrue(controller.isCapturing)

        // Simulate frame capture
        for i in 0..<4 {
            let frame = createMockFrame(index: i, size: 4)
            let isFinal = controller.ingestFrame(frame)

            if isFinal {
                XCTAssertEqual(i, 3)
                XCTAssertTrue(controller.captureComplete)
            }
        }

        // Build tensor
        guard let tensor = controller.buildCubeTensor() else {
            XCTFail("Failed to build tensor")
            return
        }

        XCTAssertEqual(tensor.sideN, 4)
        XCTAssertEqual(tensor.frames.count, 4)

        // Convert to data model
        let dataModel = tensor.toCubeTensorData()
        XCTAssertEqual(dataModel.size, 4)
        XCTAssertEqual(dataModel.indices.count, 64) // 4³
    }

    // MARK: - Helper Methods

    private func createMockFrame(index: Int, size: Int) -> QuantizedFrame {
        let indices = Data(repeating: UInt8(index % 256), count: size * size)
        let palette = (0..<256).map { UInt32($0) }
        return QuantizedFrame(
            width: size,
            height: size,
            indices: indices,
            palette: palette
        )
    }

    private func createMockFrames(count: Int, size: Int) -> [QuantizedFrame] {
        return (0..<count).map { createMockFrame(index: $0, size: size) }
    }
}

// MARK: - Type Availability Tests

final class TypeAvailabilityTests: XCTestCase {

    func testCriticalTypesExist() {
        // This test ensures critical types can be referenced
        // If any type is missing, this won't compile

        _ = CubeTensor.self
        _ = CubeTensorData.self
        _ = CubeClipController.self
        _ = CubePolicy.self
        _ = QuantizedFrame.self
        _ = CameraFormatInfo.self
    }

    func testNoLegacyTypes() {
        // This should NOT compile if legacy types leak into active code
        // Intentionally commented out - uncomment to verify they're gone:

        // _ = DownsizeOption.self  // Should fail
        // _ = PaletteOption.self   // Should fail
        // _ = FrontCameraManager.self  // Should fail
        // _ = SquareCameraView.self  // Should fail
    }
}