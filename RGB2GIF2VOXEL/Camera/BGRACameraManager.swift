// BGRACameraManager.swift
// BGRA-optimized camera manager for iPhone 17 Pro with proper stride handling

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Accelerate
import Combine
import SwiftUI

@MainActor
class BGRACameraManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isCapturing = false
    @Published var framesCaptured = 0
    @Published var currentFPS: Double = 0
    @Published var lastError: String?

    // MARK: - Session
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.rgb2gif.bgra.session")
    private let videoQueue = DispatchQueue(label: "com.rgb2gif.bgra.video", qos: .userInitiated)

    // MARK: - Device
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentFormat: CameraFormatInfo?

    // MARK: - Processing
    private let targetSize: Int = 256  // For 256x256x256 cube (maximum quality)
    private let maxFrames: Int = 256  // 256 frames for full temporal dimension
    private var collectedFrames: [Data] = []

    // MARK: - FPS Tracking
    private var frameTimestamps: [TimeInterval] = []

    override init() {
        super.init()
    }

    // MARK: - Setup

    func setupSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1. Find front camera (TrueDepth preferred for iPhone 17 Pro)
        guard let camera = findFrontCamera() else {
            updateError("No front camera found")
            return
        }

        currentDevice = camera

        // 2. Add camera input
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            updateError("Failed to add camera: \(error)")
            return
        }

        // 3. Configure for HD resolution to avoid memory pressure
        // iPhone 17 Pro's 18MP (4243×4243) would use 2.3GB for 64 frames!
        // Using HD (1920×1080) cropped to 1080×1080 = 4.5MB per frame = 288MB total
        session.sessionPreset = .hd1920x1080  // Limit resolution for memory safety

        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()

            // Mark that we need center crop for square
            currentFormat = CameraFormatInfo(
                width: 1920,
                height: 1080,
                cleanApertureWidth: 1080,
                cleanApertureHeight: 1080,
                isNativeSquare: false,
                needsCrop: true,
                fps: 30
            )
        } catch {
            updateError("Failed to configure camera: \(error)")
        }

        // 4. Configure BGRA output (iOS default, most reliable)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        output.alwaysDiscardsLateVideoFrames = true  // Drop frames if processing is slow

        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output

            // Configure connection
            if let connection = output.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    connection.videoRotationAngle = 0
                } else {
                    connection.videoOrientation = .portrait
                }
                connection.isVideoMirrored = true  // Mirror for selfie
            }
        }

        print("✅ BGRA Camera configured for iPhone 17 Pro")
    }

    // MARK: - Device Discovery

    private func findFrontCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTrueDepthCamera,  // iPhone X+ (preferred)
                .builtInWideAngleCamera    // Fallback
            ],
            mediaType: .video,
            position: .front
        )

        return discovery.devices.first
    }

    private func findBestSquareFormat(for device: AVCaptureDevice) -> (AVCaptureDevice.Format, CameraFormatInfo)? {
        var bestSquare: (AVCaptureDevice.Format, CameraFormatInfo)?
        var bestNonSquare: (AVCaptureDevice.Format, CameraFormatInfo)?

        for format in device.formats {
            guard let desc = format.formatDescription as CMFormatDescription? else { continue }

            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(desc, originIsAtTopLeft: true)

            let info = CameraFormatInfo(
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                cleanApertureWidth: Int(cleanAperture.size.width),
                cleanApertureHeight: Int(cleanAperture.size.height),
                isNativeSquare: abs(Double(cleanAperture.size.width) / Double(cleanAperture.size.height) - 1.0) < 0.02,
                needsCrop: false,
                fps: format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
            )

            if info.isNativeSquare {
                if bestSquare == nil || info.cleanApertureWidth > bestSquare!.1.cleanApertureWidth {
                    bestSquare = (format, info)
                }
            } else {
                if bestNonSquare == nil || (info.width * info.height) > (bestNonSquare!.1.width * bestNonSquare!.1.height) {
                    bestNonSquare = (format, info)
                }
            }
        }

        if let square = bestSquare {
            print("✅ Found native square format: \(square.1.cleanApertureWidth)×\(square.1.cleanApertureHeight)")
            return square
        } else if let nonSquare = bestNonSquare {
            print("⚠️ Using non-square format, will crop: \(nonSquare.1.width)×\(nonSquare.1.height)")
            let info = CameraFormatInfo(
                width: nonSquare.1.width,
                height: nonSquare.1.height,
                cleanApertureWidth: nonSquare.1.cleanApertureWidth,
                cleanApertureHeight: nonSquare.1.cleanApertureHeight,
                isNativeSquare: false,
                needsCrop: true,
                fps: nonSquare.1.fps
            )
            return (nonSquare.0, info)
        }

        return nil
    }

    // MARK: - Stride Compaction

    private func extractCompactBGRA(from buffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        // Check for stride padding (iOS uses 16-pixel alignment)
        if bytesPerRow == width * 4 {
            // No padding, can use directly
            return Data(bytes: baseAddress, count: width * height * 4)
        } else {
            // Has padding, must compact row by row
            var compactData = Data(capacity: width * height * 4)
            for row in 0..<height {
                let rowStart = baseAddress + (row * bytesPerRow)
                compactData.append(Data(bytes: rowStart, count: width * 4))
            }
            print("📦 Compacted BGRA: \(bytesPerRow) → \(width * 4) bytes/row")
            return compactData
        }
    }

    // MARK: - Center Crop

    private func centerCrop(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)

        if width == height { return buffer }

        let targetSize = min(width, height)
        let xOffset = (width - targetSize) / 2
        let yOffset = (height - targetSize) / 2

        var croppedBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetSize, targetSize,
            CVPixelBufferGetPixelFormatType(buffer),
            nil,
            &croppedBuffer
        )

        guard let output = croppedBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(buffer),
              let dstBase = CVPixelBufferGetBaseAddress(output) else {
            return nil
        }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)

        for y in 0..<targetSize {
            let srcRow = srcBase + (yOffset + y) * srcBytesPerRow + xOffset * 4
            let dstRow = dstBase + y * dstBytesPerRow
            memcpy(dstRow, srcRow, targetSize * 4)
        }

        return output
    }

    // MARK: - Control

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func startCapture() {
        isCapturing = true
        framesCaptured = 0
        collectedFrames.removeAll()
        frameTimestamps.removeAll()
    }

    func stopCapture() -> [Data] {
        isCapturing = false
        return collectedFrames
    }

    // MARK: - Helpers

    private func updateError(_ message: String) {
        Task { @MainActor in
            self.lastError = message
            print("❌ Camera Error: \(message)")
        }
    }

    private func updateFPS() {
        let now = CACurrentMediaTime()
        frameTimestamps.append(now)

        // Keep only last 30 timestamps
        while frameTimestamps.count > 30 {
            frameTimestamps.removeFirst()
        }

        if frameTimestamps.count > 1 {
            let duration = frameTimestamps.last! - frameTimestamps.first!
            let fps = Double(frameTimestamps.count - 1) / duration
            Task { @MainActor in
                self.currentFPS = fps
            }
        }
    }
}

// MARK: - Video Data Output Delegate

extension BGRACameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {

        updateFPS()

        guard isCapturing,
              framesCaptured < maxFrames,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Performance logging
        let logger = PerformanceLogger.shared
        let frameStartTime = CFAbsoluteTimeGetCurrent()

        // Apply center crop if needed
        let squareBuffer: CVPixelBuffer
        if currentFormat?.needsCrop == true {
            guard let cropped = centerCrop(pixelBuffer) else {
                logger.log(.warning, "Failed to crop frame \(framesCaptured)")
                return
            }
            squareBuffer = cropped
        } else {
            squareBuffer = pixelBuffer
        }

        // Extract compacted BGRA data (handles stride)
        guard let bgraData = extractCompactBGRA(from: squareBuffer) else {
            logger.log(.error, "Failed to extract BGRA from frame \(framesCaptured)")
            return
        }

        // Log frame processing time
        let processingTime = (CFAbsoluteTimeGetCurrent() - frameStartTime) * 1000
        logger.log(.performance, "Frame \(framesCaptured): \(String(format: "%.1f", processingTime))ms, size: \(bgraData.count / 1024)KB")

        // Collect frame
        collectedFrames.append(bgraData)

        Task { @MainActor in
            self.framesCaptured += 1

            // Auto-stop when we have enough frames
            if self.framesCaptured >= self.maxFrames {
                self.isCapturing = false
                logger.log(.info, "✅ Captured \(self.framesCaptured) frames successfully")
                print("✅ Captured \(self.framesCaptured) frames")
            }
        }
    }
}