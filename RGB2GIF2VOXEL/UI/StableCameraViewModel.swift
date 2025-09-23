//
//  StableCameraViewModel.swift
//  RGB2GIF2VOXEL
//
//  Stable, production-ready camera view model with comprehensive error handling
//

import Foundation
import AVFoundation
import UIKit
import Photos
import Combine
import os.log
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

@MainActor
final class StableCameraViewModel: NSObject, ObservableObject {

    // MARK: - Constants
    private enum Constants {
        static let targetFrameCount = 128  // Optimized for 128 frames
        static let targetResolution = 256  // 256x256 resolution
        static let maxRetryAttempts = 3
        static let memoryWarningThreshold = 100_000_000  // 100MB
        static let captureTimeout: TimeInterval = 30.0
    }

    // MARK: - Published State
    @Published var state: CaptureState = .ready
    @Published var frameCount: Int = 0
    @Published var progress: Double = 0
    @Published var isProcessing = false
    @Published var processingMessage = ""
    @Published var errorMessage = ""
    @Published var showingError = false
    @Published var hasFrames = false
    @Published var memoryPressure: Float = 0.0

    enum CaptureState: Equatable {
        case ready
        case preparing
        case capturing
        case processing(ProcessingPath)
        case saving
        case complete
        case error(CaptureError)

        var isActive: Bool {
            switch self {
            case .ready, .complete, .error:
                return false
            default:
                return true
            }
        }

        static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
            switch (lhs, rhs) {
            case (.ready, .ready),
                 (.preparing, .preparing),
                 (.capturing, .capturing),
                 (.saving, .saving),
                 (.complete, .complete):
                return true
            case (.processing(let lpath), .processing(let rpath)):
                return lpath == rpath
            case (.error(let lerror), .error(let rerror)):
                return lerror.localizedDescription == rerror.localizedDescription
            default:
                return false
            }
        }
    }

    enum ProcessingPath: String, Equatable {
        case rust = "Rust FFI"
        case swift = "Swift Native"
    }

    enum CaptureError: LocalizedError, Equatable {
        case cameraUnavailable
        case permissionDenied
        case captureTimeout
        case processingFailed(String)
        case saveFailed(String)
        case memoryPressure
        case unknown(String)

        static func == (lhs: CaptureError, rhs: CaptureError) -> Bool {
            switch (lhs, rhs) {
            case (.cameraUnavailable, .cameraUnavailable),
                 (.permissionDenied, .permissionDenied),
                 (.captureTimeout, .captureTimeout),
                 (.memoryPressure, .memoryPressure):
                return true
            case (.processingFailed(let lmsg), .processingFailed(let rmsg)),
                 (.saveFailed(let lmsg), .saveFailed(let rmsg)),
                 (.unknown(let lmsg), .unknown(let rmsg)):
                return lmsg == rmsg
            default:
                return false
            }
        }

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is not available on this device"
            case .permissionDenied:
                return "Camera permission is required to capture frames"
            case .captureTimeout:
                return "Capture timed out. Please try again."
            case .processingFailed(let reason):
                return "Processing failed: \(reason)"
            case .saveFailed(let reason):
                return "Failed to save: \(reason)"
            case .memoryPressure:
                return "Low memory. Please close other apps and try again."
            case .unknown(let reason):
                return "An error occurred: \(reason)"
            }
        }
    }

    // MARK: - Properties
    var statusText: String {
        switch state {
        case .ready:
            return hasFrames ? "Ready to Process" : "Ready"
        case .preparing:
            return "Preparing Camera..."
        case .capturing:
            return "Recording... (\(frameCount)/\(Constants.targetFrameCount))"
        case .processing(let path):
            return "Processing with \(path.rawValue)..."
        case .saving:
            return "Saving..."
        case .complete:
            return "Complete!"
        case .error(let error):
            return error.errorDescription ?? "Error"
        }
    }

    // MARK: - Camera Components
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.queue", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "processing.queue", qos: .userInitiated)
    private var videoOutput: AVCaptureVideoDataOutput?

    // MARK: - Data Management
    private var capturedFrames: [Data] = []
    private var isCapturing = false
    private var captureTimer: Timer?
    private var memoryMonitor: Timer?
    private let logger = Logger(subsystem: "com.rgb2gif2voxel", category: "Camera")

    // Memory management
    private var framePool: [Data] = []
    private let framePoolSize = 10

    // MARK: - Initialization
    override init() {
        super.init()
        setupMemoryMonitoring()
        setupNotifications()
    }

    deinit {
        // Cleanup will be handled by ARC and view lifecycle
    }

    // MARK: - Setup

    func setupCamera() {
        state = .preparing

        checkPermission { [weak self] authorized in
            guard let self = self else { return }

            if authorized {
                self.sessionQueue.async { [weak self] in
                    self?.configureSession()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleError(.permissionDenied)
                }
            }
        }
    }

    private func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()

            if session.inputs.isEmpty {
                Task { @MainActor [weak self] in
                    self?.handleError(.cameraUnavailable)
                }
            } else {
                session.startRunning()
                Task { @MainActor [weak self] in
                    self?.state = .ready
                }
            }
        }

        // Configure for high quality square capture
        session.sessionPreset = .hd1280x720

        // Add camera input (use front camera for iPhone 17 Pro)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            logger.error("Failed to add camera input")
            return
        }

        session.addInput(input)

        // Configure output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output
        } else {
            logger.error("Failed to add video output")
        }
    }

    // MARK: - Memory Management

    private func setupMemoryMonitoring() {
        memoryMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkMemoryPressure()
            }
        }
    }

    private func checkMemoryPressure() {
        let memInfo = ProcessInfo.processInfo
        let physicalMemory = memInfo.physicalMemory
        let memoryUsage = getMemoryUsage()

        memoryPressure = Float(memoryUsage) / Float(physicalMemory)

        if memoryUsage > Constants.memoryWarningThreshold && isCapturing {
            logger.warning("High memory usage: \(memoryUsage / 1_000_000)MB")

            // Implement adaptive quality reduction if needed
            if capturedFrames.count > Constants.targetFrameCount / 2 {
                // We have enough frames, stop early to prevent crash
                stopCapture()
                Task { @MainActor [weak self] in
                    self?.handleError(.memoryPressure)
                }
            }
        }
    }

    private func getMemoryUsage() -> Int64 {
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

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        logger.warning("Received memory warning")

        // Clear frame pool
        framePool.removeAll()

        // If we're not actively capturing, clear cached frames
        if !isCapturing && hasFrames {
            let keepCount = min(capturedFrames.count, Constants.targetFrameCount / 2)
            capturedFrames = Array(capturedFrames.prefix(keepCount))
        }
    }

    @objc private func handleAppBackground() {
        // Stop capture if app goes to background
        if isCapturing {
            stopCapture()
        }
    }

    // MARK: - Capture

    func startCapture() async {
        guard state == .ready || state == .complete else {
            logger.warning("Cannot start capture in state: \(String(describing: self.state))")
            return
        }

        // Reset state
        capturedFrames.removeAll(keepingCapacity: true)
        frameCount = 0
        progress = 0
        isCapturing = true
        state = .capturing
        hasFrames = false

        // Start timeout timer
        captureTimer = Timer.scheduledTimer(withTimeInterval: Constants.captureTimeout, repeats: false) { [weak self] _ in
            self?.handleCaptureTimeout()
        }

        logger.info("Started capture session")
    }

    private func handleCaptureTimeout() {
        if isCapturing {
            logger.error("Capture timeout after \(Constants.captureTimeout) seconds")
            stopCapture()
            Task { @MainActor [weak self] in
                self?.handleError(.captureTimeout)
            }
        }
    }

    func stopCapture() {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil

        hasFrames = !capturedFrames.isEmpty

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            if self.capturedFrames.isEmpty {
                self.state = .ready
            } else {
                self.state = .ready
                self.logger.info("Captured \(self.capturedFrames.count) frames")
            }
        }
    }

    // MARK: - Processing

    func processFrames(using path: ProcessingPath) async throws -> Data {
        state = .processing(path)
        progress = 0
        isProcessing = true

        defer {
            isProcessing = false
        }

        do {
            let result: Data

            switch path {
            case .rust:
                result = try await processWithRust()
            case .swift:
                result = try await processWithSwift()
            }

            state = .complete
            return result

        } catch {
            handleError(.processingFailed(error.localizedDescription))
            throw error
        }
    }

    private func processWithSwift() async throws -> Data {
        processingMessage = "Creating GIF with Swift..."

        // Simulate processing with progress updates
        for i in 0...10 {
            progress = Double(i) / 10.0
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Create actual GIF
        return try createGIF(from: capturedFrames)
    }

    private func processWithRust() async throws -> Data {
        processingMessage = "Processing with Rust FFI..."

        // TODO: Implement actual Rust processing
        // For now, fallback to Swift
        return try await processWithSwift()
    }

    private func createGIF(from frames: [Data]) throws -> Data {
        // Basic GIF creation logic
        guard !frames.isEmpty else {
            throw CaptureError.processingFailed("No frames to process")
        }

        let destinationData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            destinationData as CFMutableData,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw CaptureError.processingFailed("Failed to create GIF destination")
        }

        // GIF properties for looping
        let gifProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0  // infinite loop
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Frame properties (30 FPS = 0.033s per frame)
        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: 0.033
            ]
        ]

        // Convert and add each frame
        for (index, frameData) in frames.enumerated() {
            autoreleasepool {
                if let cgImage = createCGImage(from: frameData) {
                    CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)

                    // Update progress
                    Task { @MainActor [weak self] in
                        self?.progress = 0.5 + (0.5 * Double(index) / Double(frames.count))
                    }
                }
            }
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.processingFailed("Failed to finalize GIF")
        }

        return destinationData as Data
    }

    private func createCGImage(from frameData: Data) -> CGImage? {
        // Get actual dimensions from captured frames
        // HD preset is 1280x720, we need to handle this correctly
        let hdWidth = 1280
        let hdHeight = 720

        // First create CGImage from the HD frame
        return frameData.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return nil }

            // Use sRGB color space to match camera
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

            // BGRA format with premultiplied alpha (camera standard)
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: hdWidth,
                height: hdHeight,
                bitsPerComponent: 8,
                bytesPerRow: hdWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }

            guard let hdImage = context.makeImage() else { return nil }

            // Now resize to target resolution with aspect fill
            let targetSize = Constants.targetResolution

            // Calculate crop rect for square aspect
            let cropSize = min(hdWidth, hdHeight)
            let xOffset = (hdWidth - cropSize) / 2
            let yOffset = (hdHeight - cropSize) / 2

            // Crop to square
            guard let croppedImage = hdImage.cropping(to: CGRect(x: xOffset, y: yOffset, width: cropSize, height: cropSize)) else {
                return hdImage
            }

            // Create context for resized image
            guard let resizeContext = CGContext(
                data: nil,
                width: targetSize,
                height: targetSize,
                bitsPerComponent: 8,
                bytesPerRow: targetSize * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return croppedImage }

            // Draw resized
            resizeContext.draw(croppedImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

            return resizeContext.makeImage()
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: CaptureError) {
        logger.error("Error occurred: \(error.localizedDescription ?? "Unknown error")")

        state = .error(error)
        errorMessage = error.localizedDescription ?? "An error occurred"
        showingError = true

        // Auto-recover after 3 seconds for non-critical errors
        switch error {
        case .captureTimeout, .processingFailed:
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.resetToReady()
            }
        default:
            break
        }
    }

    func resetToReady() {
        state = .ready
        showingError = false
        errorMessage = ""
        progress = 0
        isProcessing = false
    }

    // MARK: - Cleanup

    func performCleanup() {
        cleanup()
    }

    private func cleanup() {
        captureTimer?.invalidate()
        memoryMonitor?.invalidate()

        if session.isRunning {
            session.stopRunning()
        }

        capturedFrames.removeAll()
        framePool.removeAll()

        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension StableCameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {

        guard isCapturing,
              frameCount < Constants.targetFrameCount,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Process frame on background queue to avoid blocking
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            autoreleasepool {
                if let frameData = self.pixelBufferToData(pixelBuffer) {
                    self.capturedFrames.append(frameData)

                    Task { @MainActor [weak self] in
                        guard let self = self else { return }

                        self.frameCount = self.capturedFrames.count
                        self.progress = Double(self.frameCount) / Double(Constants.targetFrameCount)

                        if self.frameCount >= Constants.targetFrameCount {
                            self.stopCapture()
                        }
                    }
                }
            }
        }
    }

    private func pixelBufferToData(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Handle stride properly - create compact data without padding
        if bytesPerRow == width * 4 {
            // No padding, can copy directly
            return Data(bytes: baseAddress, count: width * height * 4)
        } else {
            // Has row padding, need to compact
            var compactData = Data(capacity: width * height * 4)
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

            for row in 0..<height {
                let rowStart = ptr.advanced(by: row * bytesPerRow)
                compactData.append(rowStart, count: width * 4)
            }

            return compactData
        }
    }
}