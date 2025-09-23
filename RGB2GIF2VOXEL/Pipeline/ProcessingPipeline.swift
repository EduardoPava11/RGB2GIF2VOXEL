//
//  ProcessingPipeline.swift
//  RGB2GIF2VOXEL
//
//  Actor-based processing pipeline for frame processing with backpressure management
//

import Foundation
import CoreVideo
import AVFoundation
import Accelerate
import os

/// Actor-based processing pipeline that handles frame processing off the main thread
public actor ProcessingPipeline {

    // MARK: - Configuration

    public struct Configuration {
        let targetSize: Int
        let paletteSize: Int
        let strictDeterminism: Bool
        let maxProcessingBacklog: Int
        let adaptiveQuality: Bool

        public init(
            targetSize: Int = 128,
            paletteSize: Int = 256,
            strictDeterminism: Bool = true,
            maxProcessingBacklog: Int = 5,
            adaptiveQuality: Bool = true
        ) {
            self.targetSize = targetSize
            self.paletteSize = paletteSize
            self.strictDeterminism = strictDeterminism
            self.maxProcessingBacklog = maxProcessingBacklog
            self.adaptiveQuality = adaptiveQuality
        }
    }

    // MARK: - State

    private var configuration: Configuration
    private let pixelBufferPool: CVPixelBufferPool?
    private var rustProcessor: YinGifProcessor?
    private var processingQueue: [ProcessingTask] = []
    private var isProcessing = false
    private var lastProcessedTimestamp: CMTime = .zero
    private var frameDropCount = 0
    private var processedFrameCount = 0

    // Adaptive quality state
    private var currentTargetSize: Int
    private var currentPaletteSize: Int
    private var thermalState: ProcessInfo.ThermalState = .nominal

    // Metrics
    private var averageProcessingTime: TimeInterval = 0
    private var peakMemoryUsage: Int = 0

    // MARK: - Types

    private struct ProcessingTask {
        let pixelBuffer: CVPixelBuffer
        let timestamp: CMTime
        let frameIndex: Int
        let completion: (Result<QuantizedFrame, Error>) -> Void
    }

    // MARK: - Initialization

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.currentTargetSize = configuration.targetSize
        self.currentPaletteSize = configuration.paletteSize
        // rustProcessor will be initialized lazily

        // Create pixel buffer pool for optimal memory usage
        var poolAttributes: [String: Any] = [:]
        poolAttributes[kCVPixelBufferPoolMinimumBufferCountKey as String] = 3
        poolAttributes[kCVPixelBufferPoolMaximumBufferAgeKey as String] = 1.0

        var pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: configuration.targetSize,
            kCVPixelBufferHeightKey as String: configuration.targetSize,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        self.pixelBufferPool = pool

        // Start monitoring thermal state
        Task {
            await startThermalMonitoring()
        }
    }

    // MARK: - Public Interface

    /// Process a frame with backpressure management
    public func processFrame(
        _ pixelBuffer: CVPixelBuffer,
        timestamp: CMTime,
        frameIndex: Int
    ) async throws -> QuantizedFrame {
        // Check backpressure
        if await shouldDropFrame(timestamp: timestamp) {
            frameDropCount += 1
            throw PipelineProcessingError.frameDropped(reason: "Backpressure limit reached")
        }

        // Adaptive quality adjustment
        if configuration.adaptiveQuality {
            await adjustQualityForThermalState()
        }

        // Create processing task
        return try await withCheckedThrowingContinuation { continuation in
            let task = ProcessingTask(
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                frameIndex: frameIndex,
                completion: { result in
                    continuation.resume(with: result)
                }
            )

            processingQueue.append(task)
            Task {
                await processNextInQueue()
            }
        }
    }

    /// Get current metrics
    public func getMetrics() -> PipelineRuntimeMetrics {
        PipelineRuntimeMetrics(
            processedFrames: processedFrameCount,
            droppedFrames: frameDropCount,
            averageProcessingTime: averageProcessingTime,
            currentTargetSize: currentTargetSize,
            currentPaletteSize: currentPaletteSize,
            thermalState: thermalState,
            peakMemoryUsage: peakMemoryUsage
        )
    }

    /// Update configuration
    public func updateConfiguration(_ newConfig: Configuration) {
        self.configuration = newConfig
        self.currentTargetSize = newConfig.targetSize
        self.currentPaletteSize = newConfig.paletteSize
    }

    // MARK: - Private Processing

    private func processNextInQueue() async {
        guard !isProcessing, let task = processingQueue.first else { return }

        isProcessing = true
        processingQueue.removeFirst()

        let startTime = CACurrentMediaTime()

        do {
            // Downsample if needed
            let targetBuffer = try await downsampleIfNeeded(task.pixelBuffer)

            // Convert to BGRA data
            let bgraData = try extractBGRAData(from: targetBuffer)

            // Initialize processor if needed
            if rustProcessor == nil {
                rustProcessor = await MainActor.run {
                    YinGifProcessor()
                }
            }

            // Process with Rust FFI
            let quantizedFrame = try await rustProcessor!.processFrameAsync(
                bgraData: bgraData,
                width: currentTargetSize,
                height: currentTargetSize,
                targetSize: currentTargetSize,
                paletteSize: currentPaletteSize
            )

            // Update metrics
            let processingTime = CACurrentMediaTime() - startTime
            updateProcessingMetrics(time: processingTime)
            processedFrameCount += 1
            lastProcessedTimestamp = task.timestamp

            task.completion(.success(quantizedFrame))
        } catch {
            await MainActor.run {
                Log.processing.error("Failed to process frame: \(error)")
            }
            task.completion(.failure(error))
        }

        isProcessing = false

        // Process next in queue
        if !processingQueue.isEmpty {
            await processNextInQueue()
        }
    }

    private func shouldDropFrame(timestamp: CMTime) -> Bool {
        // Strict determinism: never drop frames
        if configuration.strictDeterminism {
            return false
        }

        // Check processing backlog
        if processingQueue.count >= configuration.maxProcessingBacklog {
            // Log on MainActor
            let count = processingQueue.count
            Task { @MainActor in
                Log.processing.warning("Dropping frame due to backlog: \(count)")
            }
            return true
        }

        // Check timestamp monotonicity
        if timestamp <= lastProcessedTimestamp {
            // Log on MainActor
            Task { @MainActor in
                Log.processing.warning("Dropping out-of-order frame")
            }
            return true
        }

        return false
    }

    private func downsampleIfNeeded(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Already at target size
        if width == currentTargetSize && height == currentTargetSize {
            return pixelBuffer
        }

        // Use vImage for high-quality downsampling
        return try downsampleWithVImage(
            pixelBuffer,
            targetWidth: currentTargetSize,
            targetHeight: currentTargetSize
        )
    }

    private func downsampleWithVImage(
        _ source: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> CVPixelBuffer {
        // Lock source buffer
        CVPixelBufferLockBaseAddress(source, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

        // Create destination buffer from pool or allocate
        var destination: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination)
        }

        if destination == nil {
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight
            ]

            CVPixelBufferCreate(
                kCFAllocatorDefault,
                targetWidth,
                targetHeight,
                kCVPixelFormatType_32BGRA,
                pixelBufferAttributes as CFDictionary,
                &destination
            )
        }

        guard let dest = destination else {
            throw PipelineProcessingError.bufferAllocationFailed
        }

        CVPixelBufferLockBaseAddress(dest, [])
        defer { CVPixelBufferUnlockBaseAddress(dest, []) }

        // Setup vImage buffers
        var sourceBuffer = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(source),
            height: vImagePixelCount(CVPixelBufferGetHeight(source)),
            width: vImagePixelCount(CVPixelBufferGetWidth(source)),
            rowBytes: CVPixelBufferGetBytesPerRow(source)
        )

        var destBuffer = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(dest),
            height: vImagePixelCount(targetHeight),
            width: vImagePixelCount(targetWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(dest)
        )

        // High-quality Lanczos scaling
        let error = vImageScale_ARGB8888(
            &sourceBuffer,
            &destBuffer,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        guard error == kvImageNoError else {
            throw PipelineProcessingError.downsamplingFailed
        }

        return dest
    }

    private func extractBGRAData(from pixelBuffer: CVPixelBuffer) throws -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PipelineProcessingError.invalidPixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Copy to contiguous buffer
        let dataSize = width * height * 4
        let data = Data(bytes: baseAddress, count: bytesPerRow * height)

        // If stride matches width, return as-is
        if bytesPerRow == width * 4 {
            return data
        }

        // Otherwise, copy row by row to remove padding
        var contiguousData = Data(capacity: dataSize)
        let basePtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let rowStart = basePtr.advanced(by: y * bytesPerRow)
            contiguousData.append(rowStart, count: width * 4)
        }

        return contiguousData
    }

    // MARK: - Adaptive Quality

    private func adjustQualityForThermalState() {
        switch thermalState {
        case .nominal, .fair:
            // Full quality
            currentTargetSize = configuration.targetSize
            currentPaletteSize = configuration.paletteSize

        case .serious:
            // Reduce quality by 25%
            currentTargetSize = Int(Double(configuration.targetSize) * 0.75)
            currentPaletteSize = min(128, configuration.paletteSize)
            let size = currentTargetSize
            Task { @MainActor in
                Log.processing.warning("Thermal throttling: reducing to \(size)×\(size)")
            }

        case .critical:
            // Minimum viable quality
            currentTargetSize = 64
            currentPaletteSize = 64
            Task { @MainActor in
                Log.processing.error("Critical thermal state: minimum quality mode")
            }

        @unknown default:
            break
        }
    }

    private func startThermalMonitoring() {
        // Thermal monitoring disabled - ProcessInfo.thermalStatePublisher doesn't exist
        // Could be reimplemented with Timer-based polling if needed
    }

    private func updateProcessingMetrics(time: TimeInterval) {
        // Update rolling average
        if averageProcessingTime == 0 {
            averageProcessingTime = time
        } else {
            averageProcessingTime = (averageProcessingTime * 0.9) + (time * 0.1)
        }

        // Update peak memory
        let currentMemory = getCurrentMemoryUsage()
        peakMemoryUsage = max(peakMemoryUsage, currentMemory)
    }

    private func getCurrentMemoryUsage() -> Int {
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

        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}

// MARK: - Supporting Types

public struct PipelineRuntimeMetrics {
    public let processedFrames: Int
    public let droppedFrames: Int
    public let averageProcessingTime: TimeInterval
    public let currentTargetSize: Int
    public let currentPaletteSize: Int
    public let thermalState: ProcessInfo.ThermalState
    public let peakMemoryUsage: Int
}

public enum PipelineProcessingError: Error {
    case frameDropped(reason: String)
    case bufferAllocationFailed
    case downsamplingFailed
    case invalidPixelBuffer
    case invalidInput
    case ffiError(code: Int32)
}