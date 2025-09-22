// PerformanceBenchmarks.swift
// Performance tests comparing optimized pipeline vs stock Swift Image I/O

import Testing
import AVFoundation
import CoreVideo
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import RGB2GIF2VOXEL

@Suite("Performance Benchmarks vs Stock Swift")
struct PerformanceBenchmarks {

    // MARK: - Test Configuration

    let testSizes = [132, 264, 528]
    let testFrameCount = 32
    let acceptableSpeedup = 1.5  // Must be 50% faster than stock

    // MARK: - Helper Functions

    private func createTestBuffer(size: Int, withStride: Bool = false) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?

        let bytesPerRow = withStride ? (size * 4 + 64) : (size * 4)  // Add padding if testing stride

        let attributes: [String: Any] = [
            kCVPixelBufferBytesPerRowAlignmentKey as String: bytesPerRow,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            size, size,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        // Fill with test pattern
        CVPixelBufferLockBaseAddress(pixelBuffer!, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer!) {
            let ptr = baseAddress.assumingMemoryBound(to: UInt32.self)
            for i in 0..<(size * size) {
                ptr[i] = UInt32.random(in: 0...0xFFFFFFFF)  // Random colors
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, [])

        return pixelBuffer!
    }

    // MARK: - Stock Swift Implementation (Baseline)

    private func processFrameStockSwift(_ pixelBuffer: CVPixelBuffer, targetSize: Int) -> Data? {
        // Standard Swift approach: CVPixelBuffer → UIImage → resize → GIF

        // Step 1: Convert to UIImage (common but inefficient)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)

        // Step 2: Resize using UIKit (creates copies)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSize, height: targetSize))
        let resized = renderer.image { _ in
            uiImage.draw(in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        }

        // Step 3: Convert to GIF frame using Image I/O
        guard let resizedCGImage = resized.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.gif.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, resizedCGImage, nil)
        CGImageDestinationFinalize(destination)

        return data as Data
    }

    // MARK: - Performance Tests

    @Test("Zero-copy processing beats stock Swift by >50%")
    func benchmarkZeroCopyVsStock() async throws {
        let processor = OptimizedCameraProcessor()
        let targetSize = 132

        // Create test buffer without stride (best case)
        let testBuffer = createTestBuffer(size: 1440)

        // Benchmark stock Swift
        let stockStart = CACurrentMediaTime()
        for _ in 0..<10 {
            _ = processFrameStockSwift(testBuffer, targetSize: targetSize)
        }
        let stockTime = (CACurrentMediaTime() - stockStart) / 10

        // Benchmark optimized pipeline
        processor.setupBufferPool(width: targetSize, height: targetSize)

        let optimizedStart = CACurrentMediaTime()
        for _ in 0..<10 {
            let expectation = TestExpectation()

            processor.processFrameZeroCopy(testBuffer, targetSize: targetSize, paletteSize: 256) { result in
                expectation.fulfill()
            }

            await expectation.fulfillment()
        }
        let optimizedTime = (CACurrentMediaTime() - optimizedStart) / 10

        let speedup = stockTime / optimizedTime
        print("📊 Performance: Stock=\(stockTime*1000)ms, Optimized=\(optimizedTime*1000)ms, Speedup=\(speedup)x")

        #expect(speedup > acceptableSpeedup,
                "Optimized pipeline must be >\(acceptableSpeedup)x faster than stock")
    }

    @Test("Stride handling doesn't degrade performance >10%")
    func benchmarkStrideOverhead() async throws {
        let processor = OptimizedCameraProcessor()
        let targetSize = 132

        // Test with packed buffer (no stride)
        let packedBuffer = createTestBuffer(size: 1440, withStride: false)

        let packedStart = CACurrentMediaTime()
        for _ in 0..<10 {
            let expectation = TestExpectation()
            processor.processFrameZeroCopy(packedBuffer, targetSize: targetSize, paletteSize: 256) { _ in
                expectation.fulfill()
            }
            await expectation.fulfillment()
        }
        let packedTime = (CACurrentMediaTime() - packedStart) / 10

        // Test with strided buffer
        let stridedBuffer = createTestBuffer(size: 1440, withStride: true)

        let stridedStart = CACurrentMediaTime()
        for _ in 0..<10 {
            let expectation = TestExpectation()
            processor.processFrameZeroCopy(stridedBuffer, targetSize: targetSize, paletteSize: 256) { _ in
                expectation.fulfill()
            }
            await expectation.fulfillment()
        }
        let stridedTime = (CACurrentMediaTime() - stridedStart) / 10

        let overhead = ((stridedTime - packedTime) / packedTime) * 100
        print("📊 Stride overhead: \(overhead)%")

        #expect(overhead < 10, "Stride compaction overhead must be <10%")
    }

    @Test("Memory pressure: No leaks processing 1000 frames")
    func benchmarkMemoryStability() async throws {
        let processor = OptimizedCameraProcessor()
        processor.setupBufferPool(width: 132, height: 132)

        let testBuffer = createTestBuffer(size: 1440)

        // Record initial memory
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

        let initialMemory = info.resident_size

        // Process many frames
        for i in 0..<1000 {
            let expectation = TestExpectation()

            processor.processFrameZeroCopy(testBuffer, targetSize: 132, paletteSize: 256) { _ in
                expectation.fulfill()
            }

            await expectation.fulfillment(timeout: 1.0)

            if i % 100 == 0 {
                // Check memory growth
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         withUnsafeMutablePointer(to: &info) {
                             $0.withMemoryRebound(to: integer_t.self, capacity: 1) { $0 }
                         },
                         &count)

                let currentMemory = info.resident_size
                let growth = Double(currentMemory - initialMemory) / Double(1024 * 1024)
                print("Frame \(i): Memory growth = \(growth) MB")
            }
        }

        // Final memory check
        task_info(mach_task_self_,
                 task_flavor_t(MACH_TASK_BASIC_INFO),
                 withUnsafeMutablePointer(to: &info) {
                     $0.withMemoryRebound(to: integer_t.self, capacity: 1) { $0 }
                 },
                 &count)

        let finalMemory = info.resident_size
        let totalGrowth = Double(finalMemory - initialMemory) / Double(1024 * 1024)

        #expect(totalGrowth < 50, "Memory growth must be <50MB after 1000 frames")
    }

    @Test("LZFSE compression achieves >50% ratio")
    func benchmarkCompression() throws {
        let processor = OptimizedCameraProcessor()

        // Create test tensor data (simulate N×N×N cube)
        let size = 132
        var tensorData = Data(capacity: size * size * size)
        for _ in 0..<(size * size * size) {
            tensorData.append(UInt8.random(in: 0...255))
        }

        // Test LZFSE (quality)
        let lzfseStart = CACurrentMediaTime()
        let lzfseCompressed = processor.compressTensorLZFSE(tensorData)
        let lzfseTime = CACurrentMediaTime() - lzfseStart

        // Test LZ4 (speed)
        let lz4Start = CACurrentMediaTime()
        let lz4Compressed = processor.compressTensorLZ4(tensorData)
        let lz4Time = CACurrentMediaTime() - lz4Start

        let lzfseRatio = Double(lzfseCompressed?.count ?? 0) / Double(tensorData.count)
        let lz4Ratio = Double(lz4Compressed?.count ?? 0) / Double(tensorData.count)

        print("📊 LZFSE: \(lzfseRatio*100)% in \(lzfseTime*1000)ms")
        print("📊 LZ4: \(lz4Ratio*100)% in \(lz4Time*1000)ms")

        #expect(lzfseRatio < 0.5, "LZFSE must achieve >50% compression")
        #expect(lz4Time < lzfseTime * 0.5, "LZ4 must be >2x faster than LZFSE")
    }

    @Test("P95 frame time stays under 33ms (30 FPS)")
    func benchmarkFrameTimeConsistency() async throws {
        let processor = OptimizedCameraProcessor()
        processor.setupBufferPool(width: 132, height: 132)

        let testBuffer = createTestBuffer(size: 1440)
        var frameTimes: [TimeInterval] = []

        // Process 100 frames and record times
        for _ in 0..<100 {
            let frameStart = CACurrentMediaTime()
            let expectation = TestExpectation()

            processor.processFrameZeroCopy(testBuffer, targetSize: 132, paletteSize: 256) { _ in
                let frameTime = CACurrentMediaTime() - frameStart
                frameTimes.append(frameTime)
                expectation.fulfill()
            }

            await expectation.fulfillment()
        }

        // Calculate P95
        frameTimes.sort()
        let p95Index = Int(Double(frameTimes.count) * 0.95)
        let p95Time = frameTimes[p95Index] * 1000  // Convert to ms

        print("📊 P95 frame time: \(p95Time)ms")

        #expect(p95Time < 33, "P95 frame time must be <33ms for 30 FPS")
    }
}

// MARK: - Test Expectation Helper

class TestExpectation {
    private var continuation: CheckedContinuation<Void, Never>?

    func fulfillment(timeout: TimeInterval = 1.0) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func fulfill() {
        continuation?.resume()
        continuation = nil
    }
}