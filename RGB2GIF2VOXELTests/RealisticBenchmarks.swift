// RealisticBenchmarks.swift
// ACTUAL performance measurements, no BS claims

import Testing
import AVFoundation
import CoreVideo
import UIKit
import ImageIO
@testable import RGB2GIF2VOXEL

@Suite("Realistic Performance Benchmarks")
struct RealisticBenchmarks {

    // MARK: - Baseline Measurements

    @Test("Measure ACTUAL stock Swift Image I/O performance")
    func measureStockSwiftBaseline() throws {
        // Create realistic test data (1440x1440 like iPhone camera)
        let testBuffer = createRealisticTestBuffer(width: 1440, height: 1440)

        // Measure 100 iterations for stability
        let iterations = 100
        var times: [TimeInterval] = []

        for _ in 0..<iterations {
            let start = CACurrentMediaTime()

            // Stock Swift approach
            _ = processWithStockImageIO(testBuffer)

            let elapsed = CACurrentMediaTime() - start
            times.append(elapsed)
        }

        // Calculate statistics
        let avgTime = times.reduce(0, +) / Double(times.count)
        let minTime = times.min() ?? 0
        let maxTime = times.max() ?? 0

        print("📊 Stock Swift Image I/O:")
        print("  Average: \(avgTime * 1000)ms")
        print("  Min: \(minTime * 1000)ms")
        print("  Max: \(maxTime * 1000)ms")

        // Store for comparison
        UserDefaults.standard.set(avgTime, forKey: "baseline_stock_swift")
    }

    @Test("Measure ACTUAL optimized pipeline performance")
    func measureOptimizedPipeline() throws {
        let processor = OptimizedCameraProcessor()
        processor.setupBufferPool(width: 132, height: 132)

        let testBuffer = createRealisticTestBuffer(width: 1440, height: 1440)

        let iterations = 100
        var times: [TimeInterval] = []

        for _ in 0..<iterations {
            let start = CACurrentMediaTime()
            let expectation = TestExpectation()

            processor.processFrameZeroCopy(testBuffer, targetSize: 132, paletteSize: 256) { _ in
                let elapsed = CACurrentMediaTime() - start
                times.append(elapsed)
                expectation.fulfill()
            }

            // Wait synchronously
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await expectation.fulfillment()
                semaphore.signal()
            }
            semaphore.wait()
        }

        let avgTime = times.reduce(0, +) / Double(times.count)
        let minTime = times.min() ?? 0
        let maxTime = times.max() ?? 0

        print("📊 Optimized Pipeline:")
        print("  Average: \(avgTime * 1000)ms")
        print("  Min: \(minTime * 1000)ms")
        print("  Max: \(maxTime * 1000)ms")

        // Calculate ACTUAL speedup
        if let baseline = UserDefaults.standard.object(forKey: "baseline_stock_swift") as? Double {
            let speedup = baseline / avgTime
            print("  🎯 ACTUAL Speedup: \(speedup)x")

            #expect(speedup > 1.0, "Should be faster than baseline")
        }
    }

    // MARK: - Component Benchmarks

    @Test("Measure CVPixelBuffer stride overhead")
    func measureStrideOverhead() throws {
        // Test with different stride values
        let sizes = [
            (width: 1440, bytesPerRow: 1440 * 4),      // No padding
            (width: 1440, bytesPerRow: 1440 * 4 + 16), // Small padding
            (width: 1440, bytesPerRow: 1440 * 4 + 64), // Large padding
        ]

        for config in sizes {
            let buffer = createTestBufferWithStride(
                width: config.width,
                height: config.width,
                bytesPerRow: config.bytesPerRow
            )

            let start = CACurrentMediaTime()

            // Process 100 times
            for _ in 0..<100 {
                _ = extractPixelData(from: buffer)
            }

            let elapsed = (CACurrentMediaTime() - start) / 100

            print("📊 Stride \(config.bytesPerRow - config.width * 4) bytes: \(elapsed * 1000)ms")
        }
    }

    @Test("Measure FFI overhead")
    func measureFFIOverhead() throws {
        let processor = YinGifProcessor()
        let testData = Data(repeating: 128, count: 1440 * 1440 * 4)

        // Measure pure FFI call overhead
        let iterations = 1000
        let start = CACurrentMediaTime()

        for _ in 0..<iterations {
            _ = try processor.processFrameSync(
                bgraData: testData,
                width: 1440,
                height: 1440,
                targetSize: 132,
                paletteSize: 256
            )
        }

        let avgTime = (CACurrentMediaTime() - start) / Double(iterations)

        print("📊 FFI Overhead: \(avgTime * 1000)ms per call")
        #expect(avgTime < 0.001, "FFI overhead should be <1ms")
    }

    // MARK: - Helper Functions

    private func createRealisticTestBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferBytesPerRowAlignmentKey: 16
            ] as CFDictionary,
            &pixelBuffer
        )

        // Fill with realistic data (not just zeros)
        CVPixelBufferLockBaseAddress(pixelBuffer!, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer!) {
            let ptr = baseAddress.assumingMemoryBound(to: UInt32.self)
            for i in 0..<(width * height) {
                // Realistic color distribution
                ptr[i] = UInt32.random(in: 0x40404040...0xC0C0C0C0)
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, [])

        return pixelBuffer!
    }

    private func createTestBufferWithStride(width: Int, height: Int, bytesPerRow: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferBytesPerRowAlignmentKey: bytesPerRow
            ] as CFDictionary,
            &pixelBuffer
        )

        return pixelBuffer!
    }

    private func processWithStockImageIO(_ pixelBuffer: CVPixelBuffer) -> Data? {
        // Typical Swift approach
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        // Resize
        let targetSize = CGSize(width: 132, height: 132)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            ctx.cgContext.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        }

        // Convert to data (simulate GIF encoding)
        return resized.pngData()
    }

    private func extractPixelData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!

        if bytesPerRow == width * 4 {
            // No stride
            return Data(bytes: baseAddress, count: width * height * 4)
        } else {
            // Remove stride
            var data = Data(capacity: width * height * 4)
            for row in 0..<height {
                let rowStart = baseAddress + row * bytesPerRow
                data.append(Data(bytes: rowStart, count: width * 4))
            }
            return data
        }
    }
}

// Simple test expectation for async
class TestExpectation {
    private var continuation: CheckedContinuation<Void, Never>?

    func fulfillment() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func fulfill() {
        continuation?.resume()
    }
}