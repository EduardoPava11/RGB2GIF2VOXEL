//
//  ImprovedCameraManager.swift
//  RGB2GIF2VOXEL
//
//  Robust camera session management with proper preview setup
//

import Foundation
import AVFoundation
import UIKit
import Combine
import os

@MainActor
public final class ImprovedCameraManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public var isSessionRunning = false
    @Published public var capturedFrames: [Data] = []
    @Published public var currentFrameCount = 0
    @Published public var error: Error?

    // MARK: - Camera Components

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.rgb2gif2voxel.camera", qos: .userInitiated)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoInput: AVCaptureDeviceInput?

    // MARK: - Configuration

    private let targetFrameCount = 256
    private var isCapturing = false
    private var frameBuffer: [Data] = []

    // MARK: - Initialization

    public override init() {
        super.init()
    }

    // MARK: - Setup

    public func setupSession() async throws {
        let signpostState = PipelineSignpost.begin(.capture)
        defer { PipelineSignpost.end(.capture, signpostState) }

        // Check permission
        let authorized = await checkCameraPermission()
        guard authorized else {
            throw PipelineError.permissionDenied("Camera access denied")
        }

        // Configure on session queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PipelineError.sessionSetupFailed("Manager deallocated"))
                    return
                }

                do {
                    try self.configureSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureSession() throws {
        Log.camera.info("Configuring camera session")

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Set session preset
        session.sessionPreset = .high

        // Add video input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw PipelineError.sessionSetupFailed("No camera available")
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw PipelineError.sessionSetupFailed("Cannot add camera input")
        }
        session.addInput(input)
        videoInput = input

        // Add video output for frame capture
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else {
            throw PipelineError.sessionSetupFailed("Cannot add video output")
        }
        session.addOutput(output)
        videoOutput = output

        // Configure connection
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .portrait
            connection.isEnabled = true
            Log.camera.info("Video connection configured")
        }

        Log.camera.info("✅ Camera session configured successfully")
    }

    // MARK: - Session Control

    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.session.isRunning {
                Log.camera.info("Starting camera session")
                self.session.startRunning()

                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.session.isRunning {
                Log.camera.info("Stopping camera session")
                self.session.stopRunning()

                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }

    // MARK: - Frame Capture

    public func startCapture() async throws {
        Log.pipeline.info("Starting 256-frame capture")

        let signpostState = PipelineSignpost.begin(.capture)
        defer { PipelineSignpost.end(.capture, signpostState) }

        // Reset state
        await MainActor.run {
            self.capturedFrames.removeAll()
            self.currentFrameCount = 0
            self.isCapturing = true
            self.frameBuffer.removeAll()
        }

        // Wait for frames with timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.captureCompletion = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                // Add timeout after 15 seconds
                self?.sessionQueue.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self = self else { return }
                    if self.isCapturing && self.frameBuffer.count >= 200 {
                        // Force finish if we have at least 200 frames
                        Log.camera.warning("⏱️ Capture timeout - finishing with \(self.frameBuffer.count) frames")
                        self.isCapturing = false
                        self.finishCapture()
                    }
                }
            }
        }
    }

    private var captureCompletion: ((Result<Void, Error>) -> Void)?

    // MARK: - Permission

    private func checkCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ImprovedCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isCapturing else { return }
        guard frameBuffer.count < targetFrameCount else {
            // Capture complete
            if isCapturing {
                isCapturing = false
                finishCapture()
            }
            return
        }

        // Extract frame data
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else { return }

        // Extract center square (1080x1080 from camera)
        let squareSize = min(width, height, 1080)  // Cap at 1080
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        // Use a more efficient extraction method
        let bufferSize = squareSize * squareSize * 4
        var rgbaData = Data(count: bufferSize)

        rgbaData.withUnsafeMutableBytes { destPtr in
            guard let destBase = destPtr.baseAddress else { return }

            for y in 0..<squareSize {
                let srcRow = baseAddress.advanced(by: (y + yOffset) * bytesPerRow + xOffset * 4)
                let destRow = destBase.advanced(by: y * squareSize * 4)
                memcpy(destRow, srcRow, squareSize * 4)
            }
        }

        frameBuffer.append(rgbaData)

        DispatchQueue.main.async {
            self.currentFrameCount = self.frameBuffer.count
        }

        // Log progress more frequently for debugging
        if frameBuffer.count % 16 == 0 || frameBuffer.count == targetFrameCount {
            Log.camera.info("📸 Captured \(self.frameBuffer.count)/\(self.targetFrameCount) frames")
        }

        // Check if we're stuck near the end
        if frameBuffer.count == 223 {  // 87% of 256
            Log.camera.warning("⚠️ Reached frame 223/256 - checking for stall")
        }
    }

    private func finishCapture() {
        Log.camera.info("✅ Capture complete: \(self.frameBuffer.count) frames")

        DispatchQueue.main.async {
            self.capturedFrames = self.frameBuffer
            self.captureCompletion?(.success(()))
            self.captureCompletion = nil
        }
    }
}