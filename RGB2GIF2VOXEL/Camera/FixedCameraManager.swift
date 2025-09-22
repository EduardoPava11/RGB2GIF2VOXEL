//
//  FixedCameraManager.swift
//  RGB2GIF2VOXEL
//
//  FIXED: Camera capture with proper threading and frame saving
//

import AVFoundation
import CoreVideo
import OSLog

public final class FixedCameraManager: NSObject {

    // CRITICAL: Process on background queue, not main!
    private let processingQueue = DispatchQueue(label: "com.yin.processing", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "com.yin.capture", qos: .userInitiated)

    private var cubeProcessor: CubeProcessor?
    private let logger = Logger(subsystem: "YIN.RGB2GIF2VOXEL", category: "FixedCamera")

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameCount = 0

    public override init() {
        super.init()
        Task {
            self.cubeProcessor = await CubeProcessor()
        }
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        // Configure for 1080×1080 square format
        session.sessionPreset = .hd1920x1080

        // Get front TrueDepth camera
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            logger.error("Failed to setup camera")
            return
        }

        session.addInput(input)

        // Configure output for BGRA
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        // CRITICAL: Set delegate on background queue, NOT main!
        output.setSampleBufferDelegate(self, queue: captureQueue)

        // Discard late frames for consistent throughput
        output.alwaysDiscardsLateVideoFrames = true

        session.addOutput(output)

        // Configure for square crop (center 1080×1080 from 1920×1080)
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .portrait

            // Enable stabilization if available
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        }

        self.captureSession = session
        self.videoOutput = output

        logger.info("✅ Camera configured for 1080×1080 BGRA capture")
    }

    public func startCapture() {
        captureSession?.startRunning()
        frameCount = 0
        logger.info("📹 Started capture session")
    }

    public func stopCapture() {
        captureSession?.stopRunning()
        logger.info("🛑 Stopped capture session")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FixedCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput,
                             didOutput sampleBuffer: CMSampleBuffer,
                             from connection: AVCaptureConnection) {

        // Already on background queue (captureQueue), NOT main thread!

        guard frameCount < 256 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.warning("No pixel buffer in sample")
            return
        }

        // Get dimensions
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Crop to square if needed
        let squareBuffer: CVPixelBuffer
        if width != height {
            squareBuffer = cropToSquare(pixelBuffer) ?? pixelBuffer
        } else {
            squareBuffer = pixelBuffer
        }

        frameCount += 1

        // Process frame asynchronously (already on background queue)
        Task {
            do {
                try await cubeProcessor?.processFrame(squareBuffer)

                if frameCount % 10 == 0 {
                    await MainActor.run {
                        // Update UI on main thread
                        logger.info("Processed \(self.frameCount)/256 frames")
                    }
                }
            } catch {
                logger.error("Frame processing failed: \(error)")
            }
        }
    }

    private func cropToSquare(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let size = min(width, height) // 1080

        // Calculate crop rect (center crop)
        let x = (width - size) / 2
        let y = (height - size) / 2

        // Create cropped pixel buffer
        var croppedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            size,
            size,
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &croppedBuffer
        )

        guard status == kCVReturnSuccess, let cropped = croppedBuffer else {
            return nil
        }

        // Copy center region
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(cropped, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(cropped, [])
        }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(cropped)

        let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let dstBase = CVPixelBufferGetBaseAddress(cropped)!.assumingMemoryBound(to: UInt8.self)

        for row in 0..<size {
            let srcRow = srcBase.advanced(by: (y + row) * srcBytesPerRow + x * 4)
            let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
            memcpy(dstRow, srcRow, size * 4)
        }

        return cropped
    }
}