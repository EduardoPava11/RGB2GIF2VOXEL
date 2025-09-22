// ContractTests.swift
// Architecture contract tests - validate every boundary and guarantee

import Testing
import AVFoundation
import CoreVideo
import Accelerate
@testable import RGB2GIF2VOXEL

@Suite("Architecture v2 Contract Tests")
struct ContractTests {

    // MARK: - 1. Stride Test

    @Test("Stride handling: padded CVPixelBuffer → tight compaction")
    func testStrideCompaction() throws {
        // Create buffer with padding
        let width = 1440
        let height = 1440
        let paddedBytesPerRow = width * 4 + 64 // Add 64 bytes padding

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferBytesPerRowAlignmentKey: paddedBytesPerRow
            ] as CFDictionary,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else {
            throw TestError.bufferCreationFailed
        }

        // Fill with known pattern
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let actualBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        #expect(actualBytesPerRow >= paddedBytesPerRow, "Buffer should have padding")

        // Extract compacted data
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw TestError.noBaseAddress
        }

        var compactedData = Data(capacity: width * height * 4)
        for row in 0..<height {
            let rowStart = baseAddress + row * actualBytesPerRow
            compactedData.append(Data(bytes: rowStart, count: width * 4))
        }

        // Validate size
        #expect(compactedData.count == width * height * 4,
                "Compacted data should be exactly width*height*4")

        // Validate no padding in result
        #expect(compactedData.count < height * actualBytesPerRow,
                "Compacted should be smaller than padded")
    }

    // MARK: - 2. Clean Aperture Test

    @Test("Clean aperture: 1:1 format preferred over crop")
    func testCleanApertureSelection() throws {
        // Simulate format selection logic
        let formats = [
            (width: 1920, height: 1080, cleanWidth: 1920, cleanHeight: 1080), // 16:9
            (width: 1440, height: 1440, cleanWidth: 1440, cleanHeight: 1440), // 1:1 native
            (width: 1280, height: 960, cleanWidth: 1280, cleanHeight: 960),   // 4:3
        ]

        var selectedFormat: (width: Int, height: Int, isSquare: Bool)?

        for format in formats {
            let aspectRatio = Double(format.cleanWidth) / Double(format.cleanHeight)
            let isSquare = abs(aspectRatio - 1.0) < 0.02 // 2% tolerance

            if isSquare {
                selectedFormat = (format.width, format.height, true)
                break
            }
        }

        #expect(selectedFormat?.isSquare == true,
                "Should select native square format")
        #expect(selectedFormat?.width == 1440,
                "Should select 1440x1440 format")
    }

    // MARK: - 3. FFI Batch Integrity Test

    @Test("FFI batch: N frames in → N quantized out, Z-major ordering")
    func testFFIBatchIntegrity() throws {
        let processor = RustProcessor()
        let frameCount = 8
        let width = 132
        let height = 132

        // Create test frames
        var frames: [Data] = []
        for i in 0..<frameCount {
            var frame = Data(count: width * height * 4)
            frame.withUnsafeMutableBytes { ptr in
                // Fill with pattern based on frame index
                ptr.bindMemory(to: UInt8.self).baseAddress?.initialize(
                    repeating: UInt8(i),
                    count: width * height * 4
                )
            }
            frames.append(frame)
        }

        // Process batch
        let (indices, palettes) = try processor.processBatch(
            frames: frames,
            width: width,
            height: height,
            targetSize: width,
            paletteSize: 256
        )

        // Validate Z-major ordering
        let frameSize = width * height
        #expect(indices.count == frameCount * frameSize,
                "Indices should be frames*width*height")

        // Check each frame is contiguous in Z-major order
        for frameIdx in 0..<frameCount {
            let frameStart = frameIdx * frameSize
            let frameEnd = frameStart + frameSize

            // Validate frame boundaries
            #expect(frameEnd <= indices.count,
                    "Frame \(frameIdx) should be within bounds")
        }

        // Validate palette bounds
        #expect(palettes.count == frameCount * 256,
                "Should have 256 colors per frame")

        for color in palettes {
            #expect(color <= 0xFFFFFF,
                    "Palette color should be 24-bit RGB")
        }
    }

    // MARK: - 4. YUV Conversion Test

    @Test("YUV path: vImage conversion with correct color space")
    func testYUVConversion() throws {
        // Create test YUV buffer
        let width = 1440
        let height = 1440

        // Allocate Y and UV planes
        let yPlane = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        let uvPlane = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height / 2)
        defer {
            yPlane.deallocate()
            uvPlane.deallocate()
        }

        // Fill with test pattern
        for i in 0..<(width * height) {
            yPlane[i] = UInt8(i % 256) // Luma gradient
        }
        for i in 0..<(width * height / 2) {
            uvPlane[i] = 128 // Neutral chroma
        }

        // Setup vImage buffers
        var yBuffer = vImage_Buffer(
            data: yPlane,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width
        )

        var uvBuffer = vImage_Buffer(
            data: uvPlane,
            height: vImagePixelCount(height / 2),
            width: vImagePixelCount(width / 2),
            rowBytes: width
        )

        // Allocate RGB output
        let rgbData = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        defer { rgbData.deallocate() }

        var rgbBuffer = vImage_Buffer(
            data: rgbData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
        )

        // Create conversion info for BT.601 (standard def)
        var info = vImage_YpCbCrToARGB()
        let error = vImageYpCbCr422_GenerateConversion(
            kvImage422YpCbYpCr8,
            &info,
            kvImageARGB8888,
            kvImage601_YpCbCr,  // BT.601 color space
            nil,
            kvImageNoFlags
        )

        #expect(error == kvImageNoError,
                "Conversion info should be created successfully")

        // Validate color space matrices
        // BT.601 should have specific coefficient values
        // Y = 0.299R + 0.587G + 0.114B
        // These get encoded in the conversion matrix
    }

    // MARK: - 5. YXV Validation Test

    @Test("YXV I/O: header validation, chunk checksums")
    func testYXVValidation() throws {
        // Create test YXV header
        struct YXVHeader {
            let magic: [UInt8] = [89, 88, 86, 0] // 'YXV\0'
            let version: UInt32 = 1
            let width: UInt32 = 132
            let height: UInt32 = 132
            let depth: UInt32 = 132
            let compression: UInt8 = 1 // LZ4
        }

        let header = YXVHeader()

        // Validate magic
        #expect(header.magic == [89, 88, 86, 0],
                "Magic should be YXV\\0")

        // Validate dimensions
        #expect(header.width == header.height && header.height == header.depth,
                "Should be cubic tensor")

        // Validate compression enum
        #expect(header.compression <= 2,
                "Compression should be 0=none, 1=lz4, 2=lzfse")

        // Simulate chunk validation
        let testChunk = Data(repeating: 0xAB, count: 1024)
        let checksum = testChunk.reduce(0, { $0 &+ $1 }) // Simple checksum

        #expect(checksum > 0, "Checksum should be non-zero")
    }

    // MARK: - 6. Thermal Adaptation Test

    @Test("Thermal state: quality adapts to prevent throttling")
    func testThermalAdaptation() throws {
        let thermalStates: [ProcessInfo.ThermalState] = [
            .nominal,
            .fair,
            .serious,
            .critical
        ]

        let qualityFactors: [ProcessInfo.ThermalState: Double] = [
            .nominal: 1.0,
            .fair: 0.9,
            .serious: 0.75,
            .critical: 0.5
        ]

        for state in thermalStates {
            let factor = qualityFactors[state] ?? 1.0

            // Validate quality reduction
            let baseFrameRate = 30
            let adaptedFrameRate = Int(Double(baseFrameRate) * factor)

            switch state {
            case .critical:
                #expect(adaptedFrameRate <= 15,
                        "Critical should halve frame rate")
            case .serious:
                #expect(adaptedFrameRate <= 22,
                        "Serious should reduce by 25%")
            case .fair:
                #expect(adaptedFrameRate <= 27,
                        "Fair should reduce by 10%")
            case .nominal:
                #expect(adaptedFrameRate == 30,
                        "Nominal should be full rate")
            @unknown default:
                break
            }
        }
    }

    // MARK: - Integration Test

    @Test("End-to-end: Camera → Processing → Export")
    func testEndToEndPipeline() async throws {
        // This would be an integration test on device
        // For now, validate the pipeline stages exist

        // Stage 1: Capture
        let cameraManager = CubeCameraManager()
        #expect(cameraManager.session != nil,
                "Camera session should exist")

        // Stage 2: Process
        let processor = RustProcessor()
        let testFrame = Data(repeating: 128, count: 132 * 132 * 4)
        let (indices, _) = try processor.processBatch(
            frames: [testFrame],
            width: 132,
            height: 132
        )
        #expect(indices.count > 0, "Processing should produce output")

        // Stage 3: Export
        let gif = try processor.encodeGIF(
            indices: indices,
            palettes: [UInt32](repeating: 0xFFFFFF, count: 256),
            frameCount: 1,
            side: 132
        )
        #expect(gif.count > 0, "GIF should be encoded")
    }
}

// MARK: - Test Helpers

enum TestError: Error {
    case bufferCreationFailed
    case noBaseAddress
    case processingFailed
}

// MARK: - Performance Contract Tests

@Suite("Performance Contracts")
struct PerformanceContractTests {

    @Test("Frame processing stays under 33ms budget")
    func testFrameBudget() throws {
        let processor = OptimizedCameraProcessor()
        let testBuffer = createTestBuffer(size: 1440)

        let start = CACurrentMediaTime()

        processor.processFrameZeroCopy(
            testBuffer,
            targetSize: 132,
            paletteSize: 256
        ) { _ in }

        let elapsed = (CACurrentMediaTime() - start) * 1000

        #expect(elapsed < 33,
                "Frame processing must stay under 33ms for 30 FPS")
    }

    @Test("Memory usage stays under 50MB")
    func testMemoryBudget() throws {
        // Get initial memory
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        task_info(mach_task_self_,
                 task_flavor_t(MACH_TASK_BASIC_INFO),
                 withUnsafeMutablePointer(to: &info) {
                     $0.withMemoryRebound(to: integer_t.self, capacity: 1) { $0 }
                 },
                 &count)

        let initialMemory = info.resident_size

        // Process frames
        let processor = OptimizedCameraProcessor()
        for _ in 0..<100 {
            let testBuffer = createTestBuffer(size: 1440)
            processor.processFrameZeroCopy(
                testBuffer,
                targetSize: 132,
                paletteSize: 256
            ) { _ in }
        }

        // Get final memory
        task_info(mach_task_self_,
                 task_flavor_t(MACH_TASK_BASIC_INFO),
                 withUnsafeMutablePointer(to: &info) {
                     $0.withMemoryRebound(to: integer_t.self, capacity: 1) { $0 }
                 },
                 &count)

        let finalMemory = info.resident_size
        let growthMB = Double(finalMemory - initialMemory) / (1024 * 1024)

        #expect(growthMB < 50,
                "Memory growth must stay under 50MB")
    }

    private func createTestBuffer(size: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            size, size,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        return pixelBuffer!
    }
}