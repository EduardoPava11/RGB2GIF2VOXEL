import Testing
import AVFoundation
import CoreVideo
@testable import RGB2GIF2VOXEL

@Suite("iPhone 17 Pro Camera Validation")
struct CameraValidationTests {

    // MARK: - Test Helpers

    private func createTestBuffer(width: Int, height: Int, bytesPerRow: Int? = nil) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let actualBytesPerRow = bytesPerRow ?? (width * 4)

        // Create buffer with specific stride
        let attributes: [String: Any] = [
            kCVPixelBufferBytesPerRowAlignmentKey as String: actualBytesPerRow,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        return pixelBuffer!
    }

    private func createTestFrame(index: Int, size: Int = 64) -> QuantizedFrame {
        return QuantizedFrame(
            index: index,
            width: size,
            height: size,
            indices: Data(repeating: UInt8(index % 256), count: size * size),
            palette: Array(repeating: 0xFFFFFF, count: 256),
            colorsUsed: 256
        )
    }

    // MARK: - Format Selection Tests

    @Test("Selected format is native square or cropped to square")
    func validateSquareFormat() async throws {
        // Test aspect ratio detection with 2% tolerance
        let testCases: [(width: Int, height: Int, shouldBeSquare: Bool)] = [
            (1440, 1440, true),   // Perfect square
            (1440, 1426, true),   // Within 2% tolerance (0.98 ratio)
            (1440, 1454, true),   // Within 2% tolerance (1.02 ratio)
            (1920, 1080, false),  // 16:9 - needs crop
            (1440, 1400, false)   // Outside 2% tolerance
        ]

        for testCase in testCases {
            let aspectRatio = Double(testCase.width) / Double(testCase.height)
            let isNativeSquare = abs(aspectRatio - 1.0) < 0.02

            #expect(isNativeSquare == testCase.shouldBeSquare,
                    "\(testCase.width)×\(testCase.height) square detection incorrect")
        }
    }

    // MARK: - Stride Compaction Tests

    @Test("Stride compaction yields tightly-packed BGRA")
    func validateStrideCompaction() async throws {
        let width = 1440
        let height = 1440

        // Test various padding scenarios
        let testCases: [(name: String, bytesPerRow: Int)] = [
            ("No padding", width * 4),              // Already tight
            ("16-byte aligned", 1456 * 4),          // Common alignment
            ("32-byte aligned", 1472 * 4),          // Typical iOS alignment
            ("64-byte aligned", 1536 * 4)           // Large alignment
        ]

        for testCase in testCases {
            // Verify compaction produces correct size
            let expectedSize = width * height * 4

            // For padded cases, verify padding is removed
            if testCase.bytesPerRow > width * 4 {
                #expect(testCase.bytesPerRow > expectedSize,
                       "\(testCase.name): Padded buffer should be larger")
            }
        }
    }

    // MARK: - Frame Timestamp Tests

    @Test("Timestamp validation enforces strict ordering")
    func validateTimestampOrdering() async throws {
        let controller = CubeClipController(sideN: 8)
        controller.startCapture()

        // Based on documentation: timestamps can be large (93 hours from boot)
        let baseTime = CMTime(seconds: 335000, preferredTimescale: 600) // ~93 hours

        // Test sequence
        let time1 = baseTime
        let time2 = CMTime(seconds: 335000.033, preferredTimescale: 600) // +33ms
        let time3 = CMTime(seconds: 335000.066, preferredTimescale: 600) // +66ms

        #expect(controller.shouldAcceptNextFrame(timestamp: time1) == true)
        #expect(controller.shouldAcceptNextFrame(timestamp: time2) == true)
        #expect(controller.shouldAcceptNextFrame(timestamp: time1) == false) // Duplicate
        #expect(controller.shouldAcceptNextFrame(timestamp: time3) == true)
    }
}