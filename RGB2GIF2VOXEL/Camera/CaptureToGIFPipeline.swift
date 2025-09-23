//
//  CaptureToGIFPipeline.swift
//  RGB2GIF2VOXEL
//
//  Complete wired pipeline: Capture → Downsample → Quantize → GIF
//

import Foundation
import AVFoundation
import CoreVideo
import Combine
import Photos
import os.log

private let pipelineLog = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "Pipeline")

/// Complete capture to GIF pipeline
@MainActor
public class CaptureToGIFPipeline: ObservableObject {

    // MARK: - Published State

    @Published public var isCapturing = false
    @Published public var isProcessing = false
    @Published public var capturedFrames = 0
    @Published public var progress: Double = 0
    @Published public var currentStage = ""
    @Published public var lastGIFURL: URL?
    @Published public var lastTensorURL: URL?
    @Published public var lastTensorData: Data?

    // MARK: - Pipeline Components

    private let cameraManager = CubeCameraManagerOptimized()
    private let rustProcessor = RustProcessor()
    private let downsampler = VImageDownsampler()

    // MARK: - Frame Storage

    private var frameBuffer: [Data] = []
    private let targetFrameCount = 128  // N=128 optimal configuration
    private let captureSize = 1080
    private let targetSize = 128       // N=128 optimal configuration

    // MARK: - Setup

    public func setupCamera() async {
        print("🔧 Pipeline: Setting up camera session...")

        // Setup session on the camera manager's queue
        await withCheckedContinuation { continuation in
            cameraManager.sessionQueue.async { [weak self] in
                self?.cameraManager.setupSession()
                print("✅ Pipeline: Setup complete")
                continuation.resume()
            }
        }

        // Start the session
        await withCheckedContinuation { continuation in
            cameraManager.sessionQueue.async { [weak self] in
                self?.cameraManager.session.startRunning()
                print("▶️ Pipeline: Session running")
                continuation.resume()
            }
        }
    }

    public func getCameraSession() -> AVCaptureSession {
        return cameraManager.session
    }

    // MARK: - Capture Control

    public func startCapture() async {
        guard !isCapturing else { return }

        isCapturing = true
        capturedFrames = 0
        frameBuffer.removeAll()
        frameBuffer.reserveCapacity(targetFrameCount)

        currentStage = "Capturing frames..."

        // Set up frame capture callback
        cameraManager.frameProcessor = { [weak self] pixelBuffer in
            Task { @MainActor in
                await self?.processIncomingFrame(pixelBuffer)
            }
        }

        // Start camera capture
        cameraManager.startCapture()
    }

    public func stopCapture() {
        isCapturing = false
        cameraManager.stopCapture()
        cameraManager.frameProcessor = nil
    }

    // MARK: - Frame Processing

    private func processIncomingFrame(_ pixelBuffer: CVPixelBuffer) async {
        guard isCapturing else { return }
        guard frameBuffer.count < targetFrameCount else {
            // We have enough frames, stop capturing and process
            stopCapture()
            await processFramesToGIF()
            return
        }

        // Extract BGRA data with proper stride handling
        let bgraData = extractBGRAData(from: pixelBuffer)
        frameBuffer.append(bgraData)

        capturedFrames = frameBuffer.count
        progress = Double(capturedFrames) / Double(targetFrameCount)

        os_log(.debug, log: pipelineLog, "📸 Captured frame %d/%d", capturedFrames, targetFrameCount)
    }

    private func extractBGRAData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return Data()
        }

        // Center crop to square if needed
        let squareSize = min(width, height)
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        // Handle stride and crop
        var croppedData = Data(capacity: squareSize * squareSize * 4)
        let srcPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for row in 0..<squareSize {
            let srcRow = srcPtr.advanced(by: (row + yOffset) * bytesPerRow + xOffset * 4)
            croppedData.append(srcRow, count: squareSize * 4)
        }

        return croppedData
    }

    // MARK: - Pipeline Processing

    private func processFramesToGIF() async {
        isProcessing = true
        currentStage = "Processing..."

        do {
            // Step 1: Downsample all frames
            currentStage = "Downsampling frames..."
            os_log(.info, log: pipelineLog, "🔽 Downsampling %d frames from %d to %d",
                   frameBuffer.count, captureSize, targetSize)

            let downsizedFrames = try await VImageDownsampler.batchDownsample(
                frameBuffer,
                from: captureSize,
                to: targetSize
            )

            progress = 0.3

            // Step 2: Save tensor for voxel visualization (128x128x128 RGBA)
            currentStage = "Saving tensor data..."
            let tensorData = createTensorData(from: downsizedFrames)
            let tensorURL = try saveTensor(tensorData)
            lastTensorURL = tensorURL
            lastTensorData = tensorData
            os_log(.info, log: pipelineLog, "📊 Tensor saved: %@ (%d bytes)",
                   tensorURL.lastPathComponent, tensorData.count)

            progress = 0.4

            // Step 3 & 4: Quantize and encode GIF89a in single call
            currentStage = "Creating GIF89a..."
            os_log(.info, log: pipelineLog, "🎨 Processing %d frames to GIF89a", downsizedFrames.count)

            // Convert array of Data to single array for processing
            let downsizedDataArray = downsizedFrames.map { $0 }

            // Use FFI with proper N=128 configuration
            let result = await rustProcessor.processFramesToGIF(
                frames: downsizedDataArray,
                width: targetSize,
                height: targetSize,
                includeTensor: true  // Generate voxel tensor
            )

            progress = 0.7

            guard let result = result else {
                throw CaptureError.frameProcessingFailed("Failed to process frames to GIF")
            }

            // Verify GIF89a header
            let gifData = result.gifData
            guard gifData.count > 6,
                  gifData.prefix(6) == Data("GIF89a".utf8) else {
                throw CaptureError.frameProcessingFailed("Invalid GIF89a format")
            }

            progress = 0.9

            // Step 5: Save GIF89a
            currentStage = "Saving GIF89a..."
            let gifURL = try saveGIF(gifData)
            lastGIFURL = gifURL

            os_log(.info, log: pipelineLog, "✅ GIF89a saved: %@ (%d bytes)",
                   gifURL.lastPathComponent, gifData.count)

            // Step 6: Save to Photos if permission granted
            await saveToPhotoLibrary(gifURL)

            progress = 1.0
            currentStage = "Complete!"

        } catch {
            os_log(.error, log: pipelineLog, "❌ Pipeline failed: %@", error.localizedDescription)
            currentStage = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    // MARK: - File Management

    private func saveGIF(_ data: Data) throws -> URL {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let gifPath = documentsPath.appendingPathComponent("GIFs")
        try FileManager.default.createDirectory(
            at: gifPath,
            withIntermediateDirectories: true
        )

        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = gifPath.appendingPathComponent("gif_\(timestamp).gif")
        try data.write(to: outputURL)

        return outputURL
    }

    private func saveToPhotoLibrary(_ gifURL: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else { return }

        do {
            let data = try Data(contentsOf: gifURL)
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            os_log(.info, log: pipelineLog, "📱 GIF saved to Photos")
        } catch {
            os_log(.error, log: pipelineLog, "Failed to save to Photos: %@", error.localizedDescription)
        }
    }

    // MARK: - Tensor Management

    /// Create 128x128x128 RGBA tensor data from captured frames
    private func createTensorData(from frames: [Data]) -> Data {
        // For N=128, we need exactly 128 frames at 128x128 pixels
        // Each frame is 128x128x4 (RGBA) = 65,536 bytes
        // Total tensor: 128x128x128x4 = 8,388,608 bytes (8MB)

        let tensorSize = targetSize * targetSize * targetFrameCount * 4
        var tensorData = Data(capacity: tensorSize)

        // Stack all frames into a 3D tensor
        for i in 0..<targetFrameCount {
            if i < frames.count {
                tensorData.append(frames[i])
            } else {
                // Pad with empty frames if needed (shouldn't happen with proper capture)
                let emptyFrame = Data(repeating: 0, count: targetSize * targetSize * 4)
                tensorData.append(emptyFrame)
            }
        }

        return tensorData
    }

    /// Save tensor data to disk for voxel visualization
    private func saveTensor(_ data: Data) throws -> URL {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let tensorPath = documentsPath.appendingPathComponent("Tensors")
        try FileManager.default.createDirectory(
            at: tensorPath,
            withIntermediateDirectories: true
        )

        let timestamp = Int(Date().timeIntervalSince1970)
        let outputURL = tensorPath.appendingPathComponent("tensor_\(timestamp).rgba")
        try data.write(to: outputURL)

        return outputURL
    }
}

// MARK: - Camera Manager Extension

extension CubeCameraManagerOptimized {
    /// Frame processor callback for pipeline integration
    var frameProcessor: ((CVPixelBuffer) async -> Void)? {
        get { objc_getAssociatedObject(self, &frameProcessorKey) as? ((CVPixelBuffer) async -> Void) }
        set { objc_setAssociatedObject(self, &frameProcessorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private var frameProcessorKey: UInt8 = 0