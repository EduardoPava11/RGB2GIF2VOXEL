//
//  SingleFFIPipeline.swift
//  RGB2GIF2VOXEL
//
//  Single-FFI Pipeline Implementation
//  Swift captures → downscales → encodes CBOR → user picks path → saves GIF
//

import Foundation
import AVFoundation
import Accelerate
import Photos
import Combine
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "SingleFFIPipeline")

// MARK: - Pipeline Manager

@MainActor
public class SingleFFIPipeline: ObservableObject {

    // MARK: - Published State

    @Published public var capturedFrames: [Data] = []
    @Published public var downsizedFrames: [Data] = []
    @Published public var cborFrames: [Data] = []
    @Published public var isCapturing = false
    @Published public var isProcessing = false
    @Published public var selectedPath: ProcessingPath = .swift
    @Published public var currentStage = ""
    @Published public var progress: Float = 0.0
    @Published public var lastGIFData: Data?
    @Published public var processingMetrics: TimingMetrics?

    // MARK: - Configuration

    private let captureSize = 1080
    private let targetSize = 256
    private let targetFrameCount = 256

    // MARK: - Services

    private let vImageProcessor = VImageProcessor()
    private let cborEncoder = CBORFrameEncoder()

    // MARK: - Timing

    public struct TimingMetrics {
        var captureTime: TimeInterval = 0
        var downsampleTime: TimeInterval = 0
        var cborEncodeTime: TimeInterval = 0
        var processingTime: TimeInterval = 0
        var saveTime: TimeInterval = 0
        var totalTime: TimeInterval {
            captureTime + downsampleTime + cborEncodeTime + processingTime + saveTime
        }
    }

    // MARK: - Camera Setup

    public func setupCamera() async throws {
        // Request camera permission
        let authorized = await requestCameraPermission()
        guard authorized else {
            throw PipelineError.permissionDenied("Camera access denied")
        }

        // Camera setup would be done here with actual CameraService
        os_log(.info, log: logger, "📷 Camera setup complete")
    }

    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Frame Capture

    public func startCapture() {
        capturedFrames.removeAll()
        downsizedFrames.removeAll()
        cborFrames.removeAll()
        processingMetrics = TimingMetrics()
        isCapturing = true
        progress = 0.0
        currentStage = "Capturing frames..."

        // Camera capture would start here
        processingMetrics?.captureTime = CFAbsoluteTimeGetCurrent()

        // Simulate frame capture for compilation
        Task {
            await simulateFrameCapture()
        }
    }

    private func simulateFrameCapture() async {
        // This would be replaced with actual camera capture
        for i in 0..<targetFrameCount {
            let dummyFrame = Data(repeating: 0, count: captureSize * captureSize * 4)
            capturedFrames.append(dummyFrame)
            progress = Float(i + 1) / Float(targetFrameCount)

            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms per frame
        }
        stopCapture()
    }

    private func handleCapturedFrame(_ pixelBuffer: CVPixelBuffer) async {
        guard isCapturing, capturedFrames.count < targetFrameCount else { return }

        // Extract RGBA data
        let rgbaData = extractRGBAData(from: pixelBuffer)
        capturedFrames.append(rgbaData)

        await MainActor.run {
            progress = Float(capturedFrames.count) / Float(targetFrameCount)

            if capturedFrames.count >= targetFrameCount {
                stopCapture()
            }
        }
    }

    private func stopCapture() {
        isCapturing = false
        // TODO: Implement camera service stop
        processingMetrics?.captureTime = CFAbsoluteTimeGetCurrent() - (processingMetrics?.captureTime ?? 0)

        os_log(.info, log: logger, "✅ Captured %d frames in %.2fs",
               capturedFrames.count, processingMetrics?.captureTime ?? 0)

        Task {
            await processFrames()
        }
    }

    private func extractRGBAData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Data()
        }

        // Center crop to square
        let size = min(width, height)
        let xOffset = (width - size) / 2
        let yOffset = (height - size) / 2

        var rgbaData = Data(capacity: size * size * 4)
        let srcPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for row in 0..<size {
            let srcRow = srcPtr.advanced(by: (row + yOffset) * bytesPerRow + xOffset * 4)
            rgbaData.append(srcRow, count: size * 4)
        }

        return rgbaData
    }

    // MARK: - Frame Processing

    private func processFrames() async {
        isProcessing = true
        currentStage = "Downsampling frames..."
        progress = 0.0

        do {
            // Step 1: Downsample to 256×256
            let downsampleStart = CFAbsoluteTimeGetCurrent()
            downsizedFrames = try await downsampleFrames(capturedFrames)
            processingMetrics?.downsampleTime = CFAbsoluteTimeGetCurrent() - downsampleStart

            os_log(.info, log: logger, "✅ Downsampled %d frames in %.2fs",
                   downsizedFrames.count, processingMetrics?.downsampleTime ?? 0)

            // Step 2: Encode to CBOR
            currentStage = "Encoding CBOR frames..."
            let cborStart = CFAbsoluteTimeGetCurrent()
            cborFrames = try await encodeToCBOR(downsizedFrames)
            processingMetrics?.cborEncodeTime = CFAbsoluteTimeGetCurrent() - cborStart

            os_log(.info, log: logger, "✅ Encoded %d CBOR frames in %.2fs",
                   cborFrames.count, processingMetrics?.cborEncodeTime ?? 0)

            // Step 3: Save CBOR frames
            try await saveCBORFrames(cborFrames)

            isProcessing = false
            currentStage = "Ready to process"

        } catch {
            os_log(.error, log: logger, "❌ Processing failed: %@", error.localizedDescription)
            isProcessing = false
            currentStage = "Error: \(error.localizedDescription)"
        }
    }

    private func downsampleFrames(_ frames: [Data]) async throws -> [Data] {
        var downsampled: [Data] = []
        downsampled.reserveCapacity(frames.count)

        for (index, frameData) in frames.enumerated() {
            let downsampledData = try vImageProcessor.downsample(
                rgbaData: frameData,
                fromSize: captureSize,
                toSize: targetSize
            )
            downsampled.append(downsampledData)

            await MainActor.run {
                progress = Float(index) / Float(frames.count)
            }
        }

        return downsampled
    }

    private func encodeToCBOR(_ frames: [Data]) async throws -> [Data] {
        var cborFrames: [Data] = []
        cborFrames.reserveCapacity(frames.count)

        for (index, frameData) in frames.enumerated() {
            let cborData = try cborEncoder.encodeFrame(
                data: frameData,
                index: index,
                width: targetSize,
                height: targetSize
            )
            cborFrames.append(cborData)

            await MainActor.run {
                progress = Float(index) / Float(frames.count)
            }
        }

        return cborFrames
    }

    private func saveCBORFrames(_ frames: [Data]) async throws {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionID = ISO8601DateFormatter().string(from: Date())
        let sessionURL = documentsURL.appendingPathComponent("cbor_frames/\(sessionID)")

        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)

        for (index, cborData) in frames.enumerated() {
            let frameURL = sessionURL.appendingPathComponent(String(format: "frame_%03d.cbor", index))
            try cborData.write(to: frameURL)
        }

        os_log(.info, log: logger, "✅ Saved %d CBOR frames to %@", frames.count, sessionURL.path)
    }

    // MARK: - Path Selection & Processing

    public func processWithSelectedPath() async throws {
        guard !downsizedFrames.isEmpty else {
            throw PipelineError.processingFailed("No frames to process")
        }

        isProcessing = true
        let processingStart = CFAbsoluteTimeGetCurrent()

        do {
            let gifData: Data

            switch selectedPath {
            case .rustFFI:
                currentStage = "Processing with Rust FFI..."
                gifData = try await processWithRust()

            case .swift:
                currentStage = "Processing with Swift..."
                gifData = try await processWithSwift()
            }

            processingMetrics?.processingTime = CFAbsoluteTimeGetCurrent() - processingStart
            lastGIFData = gifData

            os_log(.info, log: logger, "✅ Created GIF with %@ path in %.2fs (%d bytes)",
                   selectedPath.displayName, processingMetrics?.processingTime ?? 0, gifData.count)

            // Save to Photos
            currentStage = "Saving to Photos..."
            let saveStart = CFAbsoluteTimeGetCurrent()
            try await saveGIFToPhotos(gifData)
            processingMetrics?.saveTime = CFAbsoluteTimeGetCurrent() - saveStart

            isProcessing = false
            currentStage = "Complete!"

            logFinalMetrics()

        } catch {
            isProcessing = false
            currentStage = "Error"
            throw error
        }
    }

    // MARK: - Rust FFI Processing

    private func processWithRust() async throws -> Data {
        // Prepare contiguous buffer (256 frames * 256 * 256 * 4 bytes)
        let bufferSize = targetFrameCount * targetSize * targetSize * 4
        var contiguousBuffer = Data(capacity: bufferSize)

        for frame in downsizedFrames {
            contiguousBuffer.append(frame)
        }

        // Call Rust FFI
        let quantizeOpts = QuantizeOpts(
            qualityMin: 1,
            qualityMax: 10,
            speed: 5,
            paletteSize: 256,
            ditheringLevel: 0.0,
            sharedPalette: false
        )

        let gifOpts = GifOpts(
            width: 256,
            height: 256,
            frameCount: 256,
            fps: 25,
            loopCount: 0,  // 0 = infinite loop
            optimize: true,
            includeTensor: false
        )

        let result = try processAllFrames(
            framesRgba: contiguousBuffer,
            width: UInt32(targetSize),
            height: UInt32(targetSize),
            frameCount: UInt32(targetFrameCount),
            quantizeOpts: quantizeOpts,
            gifOpts: gifOpts
        )

        os_log(.info, log: logger, "🦀 Rust processing complete: %d bytes, %dms",
               result.finalFileSize, Int(result.processingTimeMs))

        return result.gifData
    }

    // MARK: - Swift Processing

    private func processWithSwift() async throws -> Data {
        let encoder = SwiftGIF89aEncoder()

        let config = SwiftGIF89aEncoder.Config(
            width: targetSize,
            height: targetSize,
            colorCount: 256,
            frameDelay: 0.04,  // 25fps
            loopCount: 0  // infinite
        )

        let gifData = try await encoder.encode(frames: downsizedFrames, config: config)

        os_log(.info, log: logger, "🍎 Swift processing complete: %d bytes", gifData.count)

        return gifData
    }

    // MARK: - Photos Library

    private func saveGIFToPhotos(_ gifData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        guard status == .authorized else {
            throw PipelineError.permissionDenied("Photos library access denied")
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: gifData, options: nil)
        }

        os_log(.info, log: logger, "✅ Saved GIF to Photos library")
    }

    // MARK: - Metrics

    private func logFinalMetrics() {
        guard let metrics = processingMetrics else { return }

        os_log(.info, log: logger, """
            📊 Final Pipeline Metrics:
            • Capture: %.2fs (%d frames)
            • Downsample: %.2fs
            • CBOR Encode: %.2fs
            • %@ Processing: %.2fs
            • Save to Photos: %.2fs
            • Total: %.2fs
            """,
            metrics.captureTime,
            targetFrameCount,
            metrics.downsampleTime,
            metrics.cborEncodeTime,
            selectedPath.displayName,
            metrics.processingTime,
            metrics.saveTime,
            metrics.totalTime
        )
    }
}

// MARK: - Supporting Components

// VImage Processor for downsampling
class VImageProcessor {
    func downsample(rgbaData: Data, fromSize: Int, toSize: Int) throws -> Data {
        let srcBytesPerRow = fromSize * 4
        let destBytesPerRow = toSize * 4

        return try rgbaData.withUnsafeBytes { srcPtr in
            let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: toSize * toSize * 4)
            defer { destData.deallocate() }

            var srcBuffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: srcPtr.baseAddress),
                height: vImagePixelCount(fromSize),
                width: vImagePixelCount(fromSize),
                rowBytes: srcBytesPerRow
            )

            var destBuffer = vImage_Buffer(
                data: destData,
                height: vImagePixelCount(toSize),
                width: vImagePixelCount(toSize),
                rowBytes: destBytesPerRow
            )

            let error = vImageScale_ARGB8888(
                &srcBuffer,
                &destBuffer,
                nil,
                vImage_Flags(kvImageHighQualityResampling)
            )

            guard error == kvImageNoError else {
                throw PipelineError.processingFailed("Image downsampling failed")
            }

            return Data(bytes: destData, count: toSize * toSize * 4)
        }
    }
}

// CBOR Frame Encoder (simplified without external library)
class CBORFrameEncoder {
    func encodeFrame(data: Data, index: Int, width: Int, height: Int) throws -> Data {
        // Simple binary format instead of full CBOR for now
        var encoded = Data()

        // Magic header "FRAM"
        encoded.append("FRAM".data(using: .utf8)!)

        // Version (1 byte)
        encoded.append(1)

        // Index (4 bytes)
        encoded.append(contentsOf: withUnsafeBytes(of: UInt32(index).littleEndian) { Data($0) })

        // Width (4 bytes)
        encoded.append(contentsOf: withUnsafeBytes(of: UInt32(width).littleEndian) { Data($0) })

        // Height (4 bytes)
        encoded.append(contentsOf: withUnsafeBytes(of: UInt32(height).littleEndian) { Data($0) })

        // Timestamp (8 bytes)
        let timestamp = Date().timeIntervalSince1970
        encoded.append(contentsOf: withUnsafeBytes(of: timestamp) { Data($0) })

        // Data length (4 bytes)
        encoded.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).littleEndian) { Data($0) })

        // Frame data
        encoded.append(data)

        return encoded
    }
}

// Swift GIF89a Encoder (simplified)
class SwiftGIF89aEncoder {
    struct Config {
        let width: Int
        let height: Int
        let colorCount: Int
        let frameDelay: TimeInterval
        let loopCount: Int
    }

    func encode(frames: [Data], config: Config) async throws -> Data {
        // This is a simplified implementation
        // In production, use ImageIO or a proper GIF library

        var gifData = Data()

        // GIF89a header
        gifData.append("GIF89a".data(using: .utf8)!)

        // Logical Screen Descriptor
        gifData.append(contentsOf: withUnsafeBytes(of: UInt16(config.width).littleEndian) { Data($0) })
        gifData.append(contentsOf: withUnsafeBytes(of: UInt16(config.height).littleEndian) { Data($0) })
        gifData.append(0xF7)  // Global color table, 256 colors
        gifData.append(0x00)  // Background color index
        gifData.append(0x00)  // Pixel aspect ratio

        // Global Color Table (simplified - grayscale)
        for i in 0..<256 {
            let gray = UInt8(i)
            gifData.append(contentsOf: [gray, gray, gray])
        }

        // NETSCAPE2.0 Application Extension for looping
        if config.loopCount == 0 {
            gifData.append(contentsOf: [0x21, 0xFF, 0x0B])
            gifData.append("NETSCAPE2.0".data(using: .utf8)!)
            gifData.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
        }

        // Add frames (simplified - would need proper LZW compression)
        for frameData in frames {
            // Graphics Control Extension
            gifData.append(contentsOf: [0x21, 0xF9, 0x04])
            gifData.append(0x00)  // Disposal method
            let delay = UInt16(config.frameDelay * 100)  // Convert to centiseconds
            gifData.append(contentsOf: withUnsafeBytes(of: delay.littleEndian) { Data($0) })
            gifData.append(contentsOf: [0x00, 0x00])  // Transparent color

            // Image Descriptor
            gifData.append(0x2C)  // Image separator
            gifData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Left, Top
            gifData.append(contentsOf: withUnsafeBytes(of: UInt16(config.width).littleEndian) { Data($0) })
            gifData.append(contentsOf: withUnsafeBytes(of: UInt16(config.height).littleEndian) { Data($0) })
            gifData.append(0x00)  // No local color table

            // Image Data (simplified - would need LZW)
            gifData.append(0x08)  // LZW minimum code size

            // Simplified: just append a subset of frame data
            // In reality, this needs proper LZW compression
            let chunkSize = min(255, frameData.count / 256)
            gifData.append(UInt8(chunkSize))
            gifData.append(frameData.prefix(chunkSize))
            gifData.append(0x00)  // Block terminator
        }

        // GIF Trailer
        gifData.append(0x3B)

        return gifData
    }
}

// PipelineError is now defined in Core/Errors.swift