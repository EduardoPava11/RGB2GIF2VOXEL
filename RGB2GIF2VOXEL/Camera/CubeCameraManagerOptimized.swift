// CubeCameraManagerOptimized.swift
// Production-optimized camera manager with all performance improvements

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Combine
import UIKit
import os.log

private let performanceLog = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "CameraOptimized")

@MainActor
class CubeCameraManagerOptimized: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var currentFormat: CameraFormatInfo?
    @Published var isCapturing: Bool = false
    @Published var currentFPS: Double = 0
    @Published private(set) var clipController: CubeClipController
    @Published var metrics = CaptureMetrics()

    // MARK: - Session

    let session = AVCaptureSession()
    internal let sessionQueue = DispatchQueue(label: "com.yingif.cube.session")
    private let videoDataQueue = DispatchQueue(label: "com.yingif.cube.videodata",
                                              qos: .userInitiated,
                                              attributes: [],
                                              autoreleaseFrequency: .workItem)  // Auto-release per frame

    // MARK: - Processing

    private let optimizedProcessor = OptimizedCameraProcessor()
    private var pyramidLevel: Int = CubePolicy.defaultLevel
    private var paletteSize: Int = 256

    // MARK: - Configuration

    /// Choose capture format and processing path
    public enum CaptureMode {
        case bgra       // Simple but requires conversion (current)
        case yuv420f    // Native format, maximum performance (future)
    }

    public var captureMode: CaptureMode = .bgra
    public var useLocalPalettes: Bool = true  // Per-frame palettes for better quality
    public var strictDeterminism: Bool = true // No frame drops

    // MARK: - Camera State

    private var frontCamera: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var needsSquareCrop: Bool = false

    // MARK: - Performance Monitoring

    private var frameDropCount = 0
    private var thermalMonitor: Timer?

    // MARK: - Initialization

    override init() {
        self.clipController = CubeClipController(
            sideN: CubePolicy.defaultLevel,
            paletteSize: 256
        )
        super.init()
        startThermalMonitoring()
        setupInterruptionHandling()
    }

    deinit {
        thermalMonitor?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        // Listen for session interruptions (phone calls, other apps, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )

        // Handle app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        os_log(.info, log: performanceLog, "⚠️ Session was interrupted")

        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber {
            let reason = AVCaptureSession.InterruptionReason(rawValue: userInfoValue.intValue)
            switch reason {
            case .videoDeviceNotAvailableInBackground:
                os_log(.info, log: performanceLog, "Session interrupted: video device unavailable in background")
            case .audioDeviceInUseByAnotherClient:
                os_log(.info, log: performanceLog, "Session interrupted: audio device in use")
            case .videoDeviceInUseByAnotherClient:
                os_log(.info, log: performanceLog, "Session interrupted: video device in use")
            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                os_log(.info, log: performanceLog, "Session interrupted: multiple foreground apps")
            default:
                os_log(.info, log: performanceLog, "Session interrupted: unknown reason")
            }
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        os_log(.info, log: performanceLog, "✅ Session interruption ended")

        // iOS 17 workaround: force restart session
        sessionQueue.async { [weak self] in
            if let self = self, !self.session.isRunning {
                self.session.startRunning()
                os_log(.info, log: performanceLog, "▶️ Session restarted after interruption")
            }
        }
    }

    @objc private func appDidBecomeActive() {
        // Ensure session is running when app becomes active
        sessionQueue.async { [weak self] in
            if let self = self, !self.session.isRunning {
                self.session.startRunning()
                os_log(.info, log: performanceLog, "▶️ Session restarted on app activation")
            }
        }
    }

    // MARK: - Thermal Monitoring

    private func startThermalMonitoring() {
        thermalMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.metrics.thermalState = ProcessInfo.processInfo.thermalState

                // Adapt to thermal pressure
                switch self.metrics.thermalState {
                case .critical:
                    os_log(.error, log: performanceLog, "🔥 Critical thermal state - reducing quality")
                    self.adaptToThermalPressure(quality: 0.5)
                case .serious:
                    os_log(.info, log: performanceLog, "⚠️ Serious thermal state - adjusting")
                    self.adaptToThermalPressure(quality: 0.75)
                default:
                    break
                }
            }
        }
    }

    private func adaptToThermalPressure(quality: Double) {
        // Reduce processing load under thermal pressure
        // Could reduce frame rate, resolution, or quantization quality
        // For now, just log - implement based on your needs
    }

    // MARK: - Session Setup (Optimized)

    func setupSession() {
        os_log(.info, log: performanceLog, "🔧 [SETUP] Beginning camera session setup...")

        sessionQueue.async { [weak self] in
            guard let self = self else {
                os_log(.error, log: performanceLog, "❌ [SETUP] Self deallocated during setup")
                return
            }

            os_log(.info, log: performanceLog, "🔧 [SETUP] Beginning session configuration...")
            self.session.beginConfiguration()
            defer {
                self.session.commitConfiguration()
                os_log(.info, log: performanceLog, "✅ [SETUP] Session configuration committed")
            }

            // Device discovery
            os_log(.info, log: performanceLog, "🔍 [SETUP] Discovering front camera...")
            guard let camera = self.discoverFrontCamera() else {
                os_log(.error, log: performanceLog, "❌ [SETUP] No front camera available")
                return
            }
            os_log(.info, log: performanceLog, "✅ [SETUP] Found front camera: %@", camera.localizedName)

            self.frontCamera = camera

            // Add camera input
            os_log(.info, log: performanceLog, "📹 [SETUP] Creating camera input...")
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    os_log(.info, log: performanceLog, "✅ [SETUP] Camera input added to session")
                } else {
                    os_log(.error, log: performanceLog, "❌ [SETUP] Cannot add camera input to session")
                    return
                }
            } catch {
                os_log(.error, log: performanceLog, "❌ [SETUP] Failed to create input: %@", error.localizedDescription)
                return
            }

            // Find best format
            os_log(.info, log: performanceLog, "🎬 [SETUP] Finding best camera format...")
            guard let (format, formatInfo) = self.bestSquareOrMaxFormat(for: camera) else {
                os_log(.error, log: performanceLog, "❌ [SETUP] No suitable camera format found")
                return
            }
            os_log(.info, log: performanceLog, "✅ [SETUP] Selected format: %dx%d @%dfps",
                   formatInfo.width, formatInfo.height, Int(formatInfo.fps))

            // Configure format
            os_log(.info, log: performanceLog, "⚙️ [SETUP] Configuring camera format...")
            do {
                try self.configureFormat(format, on: camera, info: formatInfo)
                self.session.sessionPreset = .inputPriority
                os_log(.info, log: performanceLog, "✅ [SETUP] Camera format configured")
            } catch {
                os_log(.error, log: performanceLog, "❌ [SETUP] Format configuration failed: %@", error.localizedDescription)
            }

            // Configure output based on mode
            os_log(.info, log: performanceLog, "📤 [SETUP] Configuring video output (mode: %@)...",
                   self.captureMode == .bgra ? "BGRA" : "YUV420f")
            let output: AVCaptureVideoDataOutput
            switch self.captureMode {
            case .bgra:
                output = self.configureBGRAOutput()
            case .yuv420f:
                output = self.configureYUV420fOutput()
            }

            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                self.videoOutput = output
                os_log(.info, log: performanceLog, "✅ [SETUP] Video output added to session")

                if let connection = output.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    connection.isVideoMirrored = true
                    connection.preferredVideoStabilizationMode = .off
                    os_log(.info, log: performanceLog, "✅ [SETUP] Video connection configured (portrait, mirrored, no stabilization)")
                } else {
                    os_log(.info, log: performanceLog, "⚠️ [SETUP] No video connection available")
                }
            } else {
                os_log(.error, log: performanceLog, "❌ [SETUP] Cannot add video output to session")
            }

            // Setup processor buffer pool
            Task { @MainActor in
                self.optimizedProcessor.setupBufferPool(
                    width: formatInfo.cleanApertureWidth,
                    height: formatInfo.cleanApertureHeight
                )
                os_log(.info, log: performanceLog, "✅ [SETUP] Processor buffer pool configured")
            }

            os_log(.info, log: performanceLog, "✅ [SETUP] Camera session fully configured")

            // Start the session after configuration
            if !self.session.isRunning {
                self.session.startRunning()
                os_log(.info, log: performanceLog, "▶️ [SETUP] Camera session started running")
            } else {
                os_log(.info, log: performanceLog, "ℹ️ [SETUP] Camera session already running")
            }

            // Log final session state
            os_log(.info, log: performanceLog, "📊 [SETUP] Final state - Inputs: %d, Outputs: %d, Running: %@",
                   self.session.inputs.count, self.session.outputs.count, self.session.isRunning ? "YES" : "NO")
        }
    }

    // MARK: - Format Discovery (Enhanced)

    private func discoverFrontCamera() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        return discoverySession.devices.first
    }

    private func bestSquareOrMaxFormat(for device: AVCaptureDevice) -> (AVCaptureDevice.Format, CameraFormatInfo)? {
        var nativeSquareFormats: [(AVCaptureDevice.Format, CameraFormatInfo)] = []
        var nonSquareFormats: [(AVCaptureDevice.Format, CameraFormatInfo)] = []

        for format in device.formats {
            guard let desc = format.formatDescription as CMFormatDescription? else { continue }

            let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let cleanAperture = CMVideoFormatDescriptionGetCleanAperture(desc, originIsAtTopLeft: true)

            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            let cleanWidth = Int(cleanAperture.size.width)
            let cleanHeight = Int(cleanAperture.size.height)

            let aspectRatio = Double(cleanWidth) / Double(cleanHeight)
            let isNativeSquare = abs(aspectRatio - 1.0) < 0.02  // 2% tolerance

            let maxFPS = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30.0

            let info = CameraFormatInfo(
                width: width,
                height: height,
                cleanApertureWidth: cleanWidth,
                cleanApertureHeight: cleanHeight,
                isNativeSquare: isNativeSquare,
                needsCrop: !isNativeSquare,
                fps: maxFPS
            )

            if isNativeSquare {
                nativeSquareFormats.append((format, info))
            } else {
                nonSquareFormats.append((format, info))
            }
        }

        // Prefer largest native square
        if let best = nativeSquareFormats.max(by: { a, b in
            (a.1.cleanApertureWidth * a.1.cleanApertureHeight) <
            (b.1.cleanApertureWidth * b.1.cleanApertureHeight)
        }) {
            os_log(.info, log: performanceLog, "✅ Native 1:1 format: %dx%d",
                   best.1.cleanApertureWidth, best.1.cleanApertureHeight)
            return best
        }

        // Fallback to highest resolution
        if let best = nonSquareFormats.max(by: { a, b in
            (a.1.width * a.1.height) < (b.1.width * b.1.height)
        }) {
            os_log(.info, log: performanceLog, "⚠️ Will crop from %dx%d",
                   best.1.width, best.1.height)
            return best
        }

        return nil
    }

    private func configureFormat(_ format: AVCaptureDevice.Format,
                                on device: AVCaptureDevice,
                                info: CameraFormatInfo) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = format
        self.needsSquareCrop = info.needsCrop

        Task { @MainActor in
            self.currentFormat = info
        }

        // Set frame rate
        let targetFPS: Double = 30.0
        for range in format.videoSupportedFrameRateRanges {
            if range.minFrameRate <= targetFPS && targetFPS <= range.maxFrameRate {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                break
            }
        }

        // Enable low light boost
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
    }

    // MARK: - Output Configuration

    private func configureBGRAOutput() -> AVCaptureVideoDataOutput {
        let output = AVCaptureVideoDataOutput()

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        output.setSampleBufferDelegate(self, queue: videoDataQueue)

        // CRITICAL: Frame drop policy
        output.alwaysDiscardsLateVideoFrames = !strictDeterminism

        os_log(.info, log: performanceLog, "📹 BGRA output configured (strict=%@)",
               strictDeterminism ? "true" : "false")

        return output
    }

    private func configureYUV420fOutput() -> AVCaptureVideoDataOutput {
        let output = AVCaptureVideoDataOutput()

        // Native format - no conversion needed
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        output.setSampleBufferDelegate(self, queue: videoDataQueue)
        output.alwaysDiscardsLateVideoFrames = !strictDeterminism

        os_log(.info, log: performanceLog, "📹 YUV 420f output configured (native format)")

        return output
    }

    // MARK: - Session Control

    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
                os_log(.info, log: performanceLog, "▶️ Session started manually")
            }
        }
    }

    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                os_log(.info, log: performanceLog, "⏹ Session stopped manually")
            }
        }
    }

    // MARK: - Capture Control

    func startCapture() {
        clipController.startCapture()
        isCapturing = true
        frameDropCount = 0
        optimizedProcessor.metrics.droppedFrames = 0
    }

    func stopCapture() {
        clipController.stopCapture()
        isCapturing = false
    }

    func reset() {
        clipController = CubeClipController(sideN: pyramidLevel, paletteSize: paletteSize)
        isCapturing = false
    }
}

// MARK: - Optimized Video Data Delegate

extension CubeCameraManagerOptimized: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Log frame delivery (only log every 30th frame to avoid spam)
        if clipController.framesCaptured % 30 == 0 {
            os_log(.debug, log: performanceLog, "📷 [FRAME] Received frame %d, timestamp: %.3f",
                   clipController.framesCaptured, CMTimeGetSeconds(timestamp))
        }

        // Check if we should accept frame
        guard clipController.shouldAcceptNextFrame(timestamp: timestamp) else {
            frameDropCount += 1
            metrics.droppedFrames = frameDropCount
            os_log(.debug, log: performanceLog, "⏭️ [FRAME] Skipping frame (drop count: %d)", frameDropCount)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            os_log(.error, log: performanceLog, "❌ [FRAME] No pixel buffer in sample buffer")
            return
        }

        // Log buffer dimensions on first frame
        if clipController.framesCaptured == 0 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            os_log(.info, log: performanceLog, "📐 [FRAME] First frame dimensions: %dx%d", width, height)
        }

        // Apply center crop if needed (using pool if possible)
        let squareBuffer: CVPixelBuffer
        if needsSquareCrop {
            guard let cropped = centerCropToSquareOptimized(pixelBuffer) else {
                os_log(.error, log: performanceLog, "❌ [FRAME] Failed to crop frame")
                return
            }
            squareBuffer = cropped

            if clipController.framesCaptured == 0 {
                let croppedWidth = CVPixelBufferGetWidth(squareBuffer)
                let croppedHeight = CVPixelBufferGetHeight(squareBuffer)
                os_log(.info, log: performanceLog, "✂️ [FRAME] Cropped to: %dx%d", croppedWidth, croppedHeight)
            }
        } else {
            squareBuffer = pixelBuffer
        }

        // Process based on capture mode
        switch captureMode {
        case .bgra:
            os_log(.debug, log: performanceLog, "🎨 [FRAME] Processing BGRA frame %d", clipController.framesCaptured)
            processBGRAFrame(squareBuffer, timestamp: timestamp)
        case .yuv420f:
            os_log(.debug, log: performanceLog, "🎨 [FRAME] Processing YUV420f frame %d", clipController.framesCaptured)
            processYUVFrame(squareBuffer, timestamp: timestamp)
        }
    }

    private func processBGRAFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // If we have a frame processor callback, use that for pipeline integration
        if let processor = frameProcessor {
            Task {
                await processor(pixelBuffer)
            }
            return
        }

        // Otherwise use the existing processing path
        let frameIndex = clipController.framesCaptured

        optimizedProcessor.processFrameZeroCopy(
            pixelBuffer,
            targetSize: pyramidLevel,
            paletteSize: paletteSize
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let processedFrame):
                // processedFrame is already a QuantizedFrame from the processor
                // Just update the index for correct ordering
                let frame = QuantizedFrame(
                    index: frameIndex,
                    data: processedFrame.data,
                    width: processedFrame.width,
                    height: processedFrame.height
                )
                Task { @MainActor in
                    let isFinal = self.clipController.ingestFrame(frame)
                    if isFinal {
                        _ = self.clipController.buildCubeTensor()
                    }
                }

            case .failure(let error):
                os_log(.error, log: performanceLog, "Frame processing error: %@",
                       error.localizedDescription)
            }
        }
    }

    private func processYUVFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let frameIndex = clipController.framesCaptured

        optimizedProcessor.processYUV420f(
            pixelBuffer,
            targetSize: pyramidLevel,
            paletteSize: paletteSize
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let processedFrame):
                // processedFrame is already a QuantizedFrame from the processor
                // Just update the index for correct ordering
                let frame = QuantizedFrame(
                    index: frameIndex,
                    data: processedFrame.data,
                    width: processedFrame.width,
                    height: processedFrame.height
                )
                Task { @MainActor in
                    let isFinal = self.clipController.ingestFrame(frame)
                    if isFinal {
                        _ = self.clipController.buildCubeTensor()
                    }
                }

            case .failure(let error):
                os_log(.error, log: performanceLog, "YUV processing error: %@",
                       error.localizedDescription)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                      didDrop sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Track dropped frames
        frameDropCount += 1
        metrics.droppedFrames = frameDropCount

        let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) as? String ?? "unknown"
        os_log(.info, log: performanceLog, "⚠️ Frame dropped: %@", reason)
    }

    // MARK: - Optimized Center Crop

    private func centerCropToSquareOptimized(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let targetSize = min(width, height)

        // Calculate crop region
        let xOffset = (width - targetSize) / 2
        let yOffset = (height - targetSize) / 2

        // Try to use pooled buffer if available
        var outputBuffer: CVPixelBuffer?

        if let pool = optimizedProcessor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        }

        if outputBuffer == nil {
            // Fallback to regular allocation
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                targetSize, targetSize,
                CVPixelBufferGetPixelFormatType(pixelBuffer),
                nil,
                &outputBuffer
            )
        }

        guard let output = outputBuffer else {
            os_log(.error, log: performanceLog, "Failed to allocate output buffer for crop")
            return nil
        }

        // Lock both buffers
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        guard let srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let dstBaseAddress = CVPixelBufferGetBaseAddress(output) else {
            os_log(.error, log: performanceLog, "Failed to get base addresses for crop")
            return nil
        }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        let bytesPerPixel = 4 // BGRA format

        // Copy cropped region row by row
        let srcPtr = srcBaseAddress.assumingMemoryBound(to: UInt8.self)
        let dstPtr = dstBaseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<targetSize {
            let srcRowStart = srcPtr.advanced(by: (y + yOffset) * srcBytesPerRow + xOffset * bytesPerPixel)
            let dstRowStart = dstPtr.advanced(by: y * dstBytesPerRow)
            memcpy(dstRowStart, srcRowStart, targetSize * bytesPerPixel)
        }

        return output
    }
    
    // MARK: - Configuration Methods
    
    func updatePyramidLevel(_ newLevel: Int) {
        pyramidLevel = newLevel
        // Reinitialize clip controller with new pyramid level
        clipController = CubeClipController(sideN: pyramidLevel, paletteSize: paletteSize)
    }
    
    func updatePaletteSize(_ newSize: Int) {
        paletteSize = newSize
        // Reinitialize clip controller with new palette size
        clipController = CubeClipController(sideN: pyramidLevel, paletteSize: paletteSize)
    }
}