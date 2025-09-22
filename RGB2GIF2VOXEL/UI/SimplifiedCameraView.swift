//
//  SimplifiedCameraView.swift
//  RGB2GIF2VOXEL
//
//  Simplified, stable camera view with clear user flow
//

import SwiftUI
import AVFoundation
import Photos
import os
import Combine
import ImageIO
import UniformTypeIdentifiers

struct SimplifiedCameraView: View {
    @StateObject private var viewModel = SimplifiedCameraViewModel()
    @State private var showingSaveSuccess = false
    @State private var savedAssetID: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Square Camera Preview
            SquareCameraPreview(session: viewModel.session)
                .overlay(captureOverlay)

            VStack {
                // Top status bar
                topStatusBar
                    .padding(.top, 50)

                Spacer()

                // Bottom controls
                bottomControls
                    .padding(.bottom, 50)
            }

            // Processing overlay
            if viewModel.isProcessing {
                processingOverlay
            }

            // Success overlay
            if showingSaveSuccess {
                successOverlay
            }
        }
        .onAppear {
            viewModel.setupCamera()
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private var topStatusBar: some View {
        HStack {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(viewModel.statusText)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // Frame counter
            if viewModel.frameCount > 0 {
                Text("\(viewModel.frameCount)/256")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .ready: return .green
        case .capturing: return .red
        case .processing: return .orange
        case .saving: return .blue
        case .complete: return .green
        case .error: return .red
        }
    }

    @ViewBuilder
    private var captureOverlay: some View {
        if viewModel.state == .capturing {
            Rectangle()
                .strokeBorder(Color.red, lineWidth: 4)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: viewModel.state)
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 30) {
            // Progress bar during capture
            if viewModel.progress > 0 && viewModel.progress < 1 {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .scaleEffect(y: 2)

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 40)
            }

            // Main capture button
            captureButton

            // Processing path selector (only shows after capture)
            if viewModel.state == .ready && viewModel.hasFrames {
                processingPathButtons
            }
        }
    }

    private var captureButton: some View {
        Button {
            Task {
                await viewModel.startCapture()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(viewModel.state == .capturing ? Color.red : Color.white)
                    .frame(width: 70, height: 70)

                if viewModel.state != .capturing {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.black)
                } else {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 25))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(viewModel.isProcessing && viewModel.state != .capturing)
        .scaleEffect(viewModel.state == .capturing ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
    }

    @ViewBuilder
    private var processingPathButtons: some View {
        HStack(spacing: 20) {
            processingButton(
                title: "Fast",
                subtitle: "Swift/ImageIO",
                color: .blue,
                action: { await viewModel.processWithSwift() }
            )

            processingButton(
                title: "Quality",
                subtitle: "Rust/NeuQuant",
                color: .orange,
                action: { await viewModel.processWithRust() }
            )
        }
        .padding(.horizontal, 40)
    }

    private func processingButton(title: String, subtitle: String, color: Color, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Activity indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                // Status text
                Text(viewModel.processingMessage)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Progress
                if viewModel.progress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.progress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(width: 200)

                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)

                Text("GIF Saved!")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Your GIF has been saved to Photos")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

                Button {
                    showingSaveSuccess = false
                    viewModel.reset()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - View Model

@MainActor
class SimplifiedCameraViewModel: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var state: CaptureState = .ready
    @Published var frameCount: Int = 0
    @Published var progress: Double = 0
    @Published var isProcessing = false
    @Published var processingMessage = ""
    @Published var errorMessage = ""
    @Published var showingError = false
    @Published var hasFrames = false

    enum CaptureState {
        case ready
        case capturing
        case processing
        case saving
        case complete
        case error
    }

    var statusText: String {
        switch state {
        case .ready: return hasFrames ? "Ready to Process" : "Ready"
        case .capturing: return "Recording..."
        case .processing: return "Processing..."
        case .saving: return "Saving..."
        case .complete: return "Complete!"
        case .error: return "Error"
        }
    }

    // MARK: - Camera Components

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.queue", qos: .userInitiated)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var capturedFrames: [Data] = []
    private var isCapturing = false
    private let targetFrameCount = 256

    // MARK: - Setup

    func setupCamera() {
        checkPermission { [weak self] authorized in
            if authorized {
                self?.sessionQueue.async {
                    self?.configureSession()
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
            session.startRunning()
        }

        // Configure for high quality square capture
        session.sessionPreset = .high

        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            Log.camera.error("Failed to add camera input")
            return
        }
        session.addInput(input)

        // Add video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else {
            Log.camera.error("Failed to add video output")
            return
        }
        session.addOutput(output)
        videoOutput = output

        // Set video orientation for portrait mode
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // Mirror for front camera if needed
            if camera.position == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        Log.camera.info("✅ Camera configured successfully")
    }

    // MARK: - Capture Control

    func startCapture() async {
        guard state == .ready else { return }

        // Reset state
        capturedFrames.removeAll()
        frameCount = 0
        progress = 0
        state = .capturing
        isCapturing = true

        // Capture will happen in delegate
        Log.camera.info("📸 Starting capture of \(self.targetFrameCount) frames")
    }

    func stopCapture() {
        isCapturing = false
        state = .ready
        hasFrames = !capturedFrames.isEmpty
        Log.camera.info("✅ Capture stopped with \(self.capturedFrames.count) frames")
    }

    // MARK: - Processing

    func processWithSwift() async {
        await processFrames(useRust: false)
    }

    func processWithRust() async {
        await processFrames(useRust: true)
    }

    private func processFrames(useRust: Bool) async {
        guard !capturedFrames.isEmpty else { return }

        state = .processing
        isProcessing = true
        processingMessage = useRust ? "Processing with Rust..." : "Processing with Swift..."

        do {
            // Downsample frames to 256x256
            processingMessage = "Downsampling frames..."
            progress = 0.2
            let downsampledFrames = try await downsampleFrames(capturedFrames)

            // Create GIF
            processingMessage = useRust ? "Creating GIF with NeuQuant..." : "Creating GIF with ImageIO..."
            progress = 0.5

            let gifData: Data
            if useRust {
                gifData = try await createGIFWithRust(downsampledFrames)
            } else {
                gifData = try await createGIFWithSwift(downsampledFrames)
            }

            // Save to Photos
            state = .saving
            processingMessage = "Saving to Photos..."
            progress = 0.9

            let asset = try await PhotosGIFSaver.saveGIF(gifData)

            // Complete!
            state = .complete
            progress = 1.0
            isProcessing = false

            Log.ui.info("✅ GIF saved successfully!")

        } catch {
            state = .error
            isProcessing = false
            errorMessage = error.localizedDescription
            showingError = true
            Log.ui.error("Failed to process GIF: \(error)")
        }
    }

    private func downsampleFrames(_ frames: [Data]) async throws -> [Data] {
        // Implement efficient downsampling
        // For now, return as-is if already 256x256
        return frames
    }

    private func createGIFWithSwift(_ frames: [Data]) async throws -> Data {
        // Use ImageIO to create proper GIF
        return try await createGIFUsingImageIO(frames: frames)
    }

    private func createGIFUsingImageIO(frames: [Data]) async throws -> Data {
        let destinationData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            destinationData as CFMutableData,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw NSError(domain: "GIF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create GIF destination"])
        }

        // GIF properties
        let gifProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0 // infinite loop
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Frame delay (25 fps = 0.04 seconds per frame)
        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: 0.04
            ]
        ]

        // Add each frame
        for frameData in frames {
            // Convert BGRA to RGBA and create CGImage
            guard let cgImage = createCGImage(from: frameData, width: 256, height: 256) else {
                continue
            }
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }

        // Finalize
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "GIF", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF"])
        }

        return destinationData as Data
    }

    private func createCGImage(from bgraData: Data, width: Int, height: Int) -> CGImage? {
        // Convert BGRA to RGBA
        var rgbaData = Data(count: bgraData.count)
        rgbaData.withUnsafeMutableBytes { (rgbaPtr: UnsafeMutableRawBufferPointer) in
            bgraData.withUnsafeBytes { (bgraPtr: UnsafeRawBufferPointer) in
                guard let rgba = rgbaPtr.baseAddress,
                      let bgra = bgraPtr.baseAddress else { return }

                for i in stride(from: 0, to: bgraData.count, by: 4) {
                    // BGRA -> RGBA
                    rgba.assumingMemoryBound(to: UInt8.self)[i] = bgra.assumingMemoryBound(to: UInt8.self)[i + 2]     // R = B
                    rgba.assumingMemoryBound(to: UInt8.self)[i + 1] = bgra.assumingMemoryBound(to: UInt8.self)[i + 1] // G = G
                    rgba.assumingMemoryBound(to: UInt8.self)[i + 2] = bgra.assumingMemoryBound(to: UInt8.self)[i]     // B = R
                    rgba.assumingMemoryBound(to: UInt8.self)[i + 3] = bgra.assumingMemoryBound(to: UInt8.self)[i + 3] // A = A
                }
            }
        }

        // Create CGImage
        return rgbaData.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return nil }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )

            return context?.makeImage()
        }
    }

    private func createGIFWithRust(_ frames: [Data]) async throws -> Data {
        // Convert BGRA frames to RGBA and prepare contiguous buffer
        var buffer = Data()
        for frameData in frames {
            // Convert BGRA to RGBA
            var rgbaFrame = Data(count: frameData.count)
            rgbaFrame.withUnsafeMutableBytes { (rgbaPtr: UnsafeMutableRawBufferPointer) in
                frameData.withUnsafeBytes { (bgraPtr: UnsafeRawBufferPointer) in
                    guard let rgba = rgbaPtr.baseAddress,
                          let bgra = bgraPtr.baseAddress else { return }

                    let rgbaBytes = rgba.assumingMemoryBound(to: UInt8.self)
                    let bgraBytes = bgra.assumingMemoryBound(to: UInt8.self)

                    for i in stride(from: 0, to: frameData.count, by: 4) {
                        // BGRA -> RGBA
                        rgbaBytes[i] = bgraBytes[i + 2]     // R = B
                        rgbaBytes[i + 1] = bgraBytes[i + 1] // G = G
                        rgbaBytes[i + 2] = bgraBytes[i]     // B = R
                        rgbaBytes[i + 3] = bgraBytes[i + 3] // A = A
                    }
                }
            }
            buffer.append(rgbaFrame)
        }

        let quantizeOpts = QuantizeOpts(
            qualityMin: 70,
            qualityMax: 100,
            speed: 5,
            paletteSize: 256,
            ditheringLevel: 1.0,
            sharedPalette: true
        )

        let gifOpts = GifOpts(
            width: 256,
            height: 256,
            frameCount: UInt16(frames.count),
            fps: 25,
            loopCount: 0,
            optimize: true,
            includeTensor: false
        )

        let result = try processAllFrames(
            framesRgba: buffer,
            width: 256,
            height: 256,
            frameCount: UInt32(frames.count),
            quantizeOpts: quantizeOpts,
            gifOpts: gifOpts
        )

        return result.gifData
    }

    func reset() {
        capturedFrames.removeAll()
        frameCount = 0
        progress = 0
        state = .ready
        hasFrames = false
    }
}

// MARK: - Camera Delegate

extension SimplifiedCameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Ensure proper orientation
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        guard isCapturing, capturedFrames.count < targetFrameCount else {
            if isCapturing && capturedFrames.count >= targetFrameCount {
                DispatchQueue.main.async {
                    self.stopCapture()
                }
            }
            return
        }

        // Extract frame
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else { return }

        // Extract 256x256 center square efficiently
        let targetSize = 256
        let sourceSize = min(width, height, 1080)
        let xOffset = (width - sourceSize) / 2
        let yOffset = (height - sourceSize) / 2

        // Create downsampled frame directly
        var frameData = Data(count: targetSize * targetSize * 4)
        frameData.withUnsafeMutableBytes { destPtr in
            guard let destBase = destPtr.baseAddress else { return }

            // Simple downsampling by picking pixels
            let step = sourceSize / targetSize
            for y in 0..<targetSize {
                for x in 0..<targetSize {
                    let srcY = y * step + yOffset
                    let srcX = x * step + xOffset
                    let srcOffset = srcY * bytesPerRow + srcX * 4
                    let destOffset = (y * targetSize + x) * 4

                    // Copy BGRA pixel
                    memcpy(destBase.advanced(by: destOffset),
                           baseAddress.advanced(by: srcOffset),
                           4)
                }
            }
        }

        capturedFrames.append(frameData)

        DispatchQueue.main.async {
            self.frameCount = self.capturedFrames.count
            self.progress = Double(self.frameCount) / Double(self.targetFrameCount)

            // Log progress
            if self.frameCount % 32 == 0 || self.frameCount == self.targetFrameCount {
                Log.camera.info("📸 Captured \(self.frameCount)/\(self.targetFrameCount)")
            }
        }
    }
}

// MARK: - Preview

struct SimplifiedCameraView_Previews: PreviewProvider {
    static var previews: some View {
        SimplifiedCameraView()
    }
}