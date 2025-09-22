//
//  CameraService.swift
//  RGB2GIF2VOXEL
//
//  Unified camera service wrapping AVCaptureSession
//

import Foundation
import AVFoundation
import Combine
import UIKit
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "CameraService")

/// Unified camera service providing clean API for camera operations
@MainActor
public class CameraService: ObservableObject {

    // MARK: - Published State

    @Published public var isSessionRunning = false
    @Published public var isCapturing = false
    @Published public var capturedFrames = 0
    @Published public var currentFPS: Double = 0
    @Published public var lastError: CameraError?

    // MARK: - Camera Manager

    private let cameraManager = CubeCameraManagerOptimized()

    // MARK: - Properties

    public var session: AVCaptureSession {
        cameraManager.session
    }

    public var currentFormat: CameraFormatInfo? {
        cameraManager.currentFormat
    }

    public var metrics: CaptureMetrics {
        cameraManager.metrics
    }

    // MARK: - Frame Delegate

    public var frameProcessor: ((CVPixelBuffer) async -> Void)? {
        get { cameraManager.frameProcessor }
        set { cameraManager.frameProcessor = newValue }
    }

    // MARK: - Initialization

    public init() {
        setupBindings()
    }

    private func setupBindings() {
        // Bind camera manager state to service
        cameraManager.$isCapturing
            .assign(to: &$isCapturing)

        cameraManager.$currentFPS
            .assign(to: &$currentFPS)
    }

    // MARK: - Permission Management

    /// Check camera permission status
    public func checkPermission() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Request camera permission
    public func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                os_log(.info, log: logger, "Camera permission %@",
                       granted ? "granted" : "denied")
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Session Management

    /// Setup camera session (call after permission granted)
    public func setupSession() async throws {
        os_log(.info, log: logger, "Setting up camera session...")

        await withCheckedContinuation { continuation in
            cameraManager.setupSession()
            continuation.resume()
        }

        // Verify session is configured
        guard !cameraManager.session.inputs.isEmpty else {
            throw CameraError.sessionConfigurationFailed
        }

        os_log(.info, log: logger, "✅ Camera session configured")
    }

    /// Start camera session
    public func startSession() {
        os_log(.info, log: logger, "Starting camera session...")
        cameraManager.startSession()
        isSessionRunning = true
    }

    /// Stop camera session
    public func stopSession() {
        os_log(.info, log: logger, "Stopping camera session...")
        cameraManager.stopSession()
        isSessionRunning = false
    }

    // MARK: - Capture Control

    /// Start capturing frames
    public func startCapture() {
        guard isSessionRunning else {
            os_log(.error, log: logger, "Cannot start capture - session not running")
            lastError = .sessionConfigurationFailed
            return
        }

        os_log(.info, log: logger, "Starting capture...")
        cameraManager.startCapture()
        capturedFrames = 0
    }

    /// Stop capturing frames
    public func stopCapture() {
        os_log(.info, log: logger, "Stopping capture...")
        cameraManager.stopCapture()
    }

    /// Reset capture state
    public func reset() {
        cameraManager.reset()
        capturedFrames = 0
    }

    // MARK: - Cube Tensor Access

    /// Get the clip controller for accessing captured frames
    public var clipController: CubeClipController {
        cameraManager.clipController
    }

    /// Build cube tensor from captured frames
    public func buildCubeTensor() -> CubeTensor? {
        return cameraManager.clipController.buildCubeTensor()
    }

    // MARK: - Preview Layer Creation

    /// Create a preview layer for the camera session
    public func createPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill

        // Set connection properties
        if let connection = layer.connection {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true  // Mirror for front camera
            }
        }

        return layer
    }
}