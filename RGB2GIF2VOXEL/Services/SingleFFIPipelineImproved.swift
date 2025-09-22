//
//  SingleFFIPipelineImproved.swift
//  RGB2GIF2VOXEL
//
//  Improved Single-FFI Pipeline with proper logging, signposts, and camera/Photos fixes
//

import Foundation
import AVFoundation
import Accelerate
import Photos
import Combine
import UIKit
import os

@MainActor
public final class SingleFFIPipelineImproved: ObservableObject {

    // MARK: - Published Properties

    @Published public var state: PipelineState = .idle
    @Published public var progress: Double = 0.0
    @Published public var currentPhase: String = ""
    @Published public var capturedFrameCount: Int = 0
    @Published public var error: Error?
    @Published public var processingMetrics: TimingMetrics?

    // MARK: - State

    public enum PipelineState: Equatable {
        case idle
        case checkingPermissions
        case capturingFrames
        case downsampling
        case encodingCBOR
        case awaitingPathSelection
        case processingSwift
        case processingRust
        case savingToPhotos
        case complete
        case failed(Error)

        public static func == (lhs: PipelineState, rhs: PipelineState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.checkingPermissions, .checkingPermissions),
                 (.capturingFrames, .capturingFrames),
                 (.downsampling, .downsampling),
                 (.encodingCBOR, .encodingCBOR),
                 (.awaitingPathSelection, .awaitingPathSelection),
                 (.processingSwift, .processingSwift),
                 (.processingRust, .processingRust),
                 (.savingToPhotos, .savingToPhotos),
                 (.complete, .complete):
                return true
            case (.failed(let e1), .failed(let e2)):
                return (e1 as NSError) == (e2 as NSError)
            default:
                return false
            }
        }
    }

    // MARK: - Components

    private let cameraManager = ImprovedCameraManager()
    private let vImageProcessor = VImageProcessor()
    private let cborEncoder = CBORFrameEncoder()

    // MARK: - Constants

    private let targetFrameCount = 256
    private let sourceSize = 1080
    private let targetSize = 256

    // MARK: - Timing

    public struct TimingMetrics {
        public var captureTime: TimeInterval = 0
        public var downsampleTime: TimeInterval = 0
        public var cborEncodeTime: TimeInterval = 0
        public var processingTime: TimeInterval = 0
        public var saveTime: TimeInterval = 0
        public var totalTime: TimeInterval = 0
    }

    // MARK: - Main Pipeline

    public func runPipeline() async {
        let pipelineState = PipelineSignpost.begin(.fullPipeline)
        defer { PipelineSignpost.end(.fullPipeline, pipelineState) }

        state = .checkingPermissions
        var metrics = TimingMetrics()
        let totalStart = Date()

        do {
            // Setup camera
            try await cameraManager.setupSession()
            cameraManager.startSession()

            // Ensure session is running
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s for camera to stabilize

            // 1. Capture frames
            state = .capturingFrames
            let captureStart = Date()
            let captureSignpost = PipelineSignpost.begin(.capture)

            // Monitor frame count during capture
            let frameCountObserver = cameraManager.$currentFrameCount
                .receive(on: DispatchQueue.main)
                .sink { [weak self] count in
                    self?.capturedFrameCount = count
                    self?.progress = Double(count) / 256.0
                }

            try await cameraManager.startCapture()
            let capturedFrames = cameraManager.capturedFrames
            frameCountObserver.cancel()

            PipelineSignpost.end(.capture, captureSignpost)
            metrics.captureTime = Date().timeIntervalSince(captureStart)
            Log.camera.info("✅ Captured \(capturedFrames.count) frames in \(metrics.captureTime, format: .fixed(precision: 2))s")

            // 2. Downsample frames
            state = .downsampling
            let downsampleStart = Date()
            let downsampleSignpost = PipelineSignpost.begin(.downsample)

            let downsampledFrames = try await downsampleFrames(capturedFrames)

            PipelineSignpost.end(.downsample, downsampleSignpost)
            metrics.downsampleTime = Date().timeIntervalSince(downsampleStart)
            Log.pipeline.info("✅ Downsampled \(downsampledFrames.count) frames in \(metrics.downsampleTime, format: .fixed(precision: 2))s")

            // 3. Encode to CBOR
            state = .encodingCBOR
            let cborStart = Date()
            let cborSignpost = PipelineSignpost.begin(.cborEncode)

            try await encodeCBORFrames(downsampledFrames)

            PipelineSignpost.end(.cborEncode, cborSignpost)
            metrics.cborEncodeTime = Date().timeIntervalSince(cborStart)
            Log.pipeline.info("✅ Encoded CBOR in \(metrics.cborEncodeTime, format: .fixed(precision: 2))s")

            // 4. Wait for user path selection
            state = .awaitingPathSelection
            currentPhase = "Select processing path"

            // This would be triggered by UI
            // For now, auto-select Rust path after 2 seconds
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // 5. Process with selected path (defaulting to Rust)
            state = .processingRust
            let processingStart = Date()

            let gifData = try await processWithRust(downsampledFrames)

            metrics.processingTime = Date().timeIntervalSince(processingStart)
            Log.ffi.info("✅ Processed GIF in \(metrics.processingTime, format: .fixed(precision: 2))s")

            // 6. Save to Photos
            state = .savingToPhotos
            let saveStart = Date()
            let saveSignpost = PipelineSignpost.begin(.savePhotos)

            let asset = try await PhotosGIFSaver.saveGIF(gifData)

            PipelineSignpost.end(.savePhotos, saveSignpost)
            metrics.saveTime = Date().timeIntervalSince(saveStart)
            Log.photos.info("✅ Saved to Photos in \(metrics.saveTime, format: .fixed(precision: 2))s")

            // Complete
            metrics.totalTime = Date().timeIntervalSince(totalStart)
            self.processingMetrics = metrics
            state = .complete

            Log.pipeline.info("""
                ✅ Pipeline complete!
                Total time: \(metrics.totalTime, format: .fixed(precision: 2))s
                - Capture: \(metrics.captureTime, format: .fixed(precision: 2))s
                - Downsample: \(metrics.downsampleTime, format: .fixed(precision: 2))s
                - CBOR: \(metrics.cborEncodeTime, format: .fixed(precision: 2))s
                - Processing: \(metrics.processingTime, format: .fixed(precision: 2))s
                - Save: \(metrics.saveTime, format: .fixed(precision: 2))s
                """)

        } catch {
            Log.pipeline.error("Pipeline failed: \(error.localizedDescription)")
            self.error = error
            state = .failed(error)
        }

        // Clean up
        cameraManager.stopSession()
    }

    // MARK: - User Path Selection

    public func selectSwiftPath() async throws -> Data {
        state = .processingSwift
        let frames = cameraManager.capturedFrames
        let downsampledFrames = try await downsampleFrames(frames)
        return try await processWithSwift(downsampledFrames)
    }

    public func selectRustPath() async throws -> Data {
        state = .processingRust
        let frames = cameraManager.capturedFrames
        let downsampledFrames = try await downsampleFrames(frames)
        return try await processWithRust(downsampledFrames)
    }

    // MARK: - Frame Processing

    private func downsampleFrames(_ frames: [Data]) async throws -> [Data] {
        try await withThrowingTaskGroup(of: Data.self) { group in
            for (index, frame) in frames.enumerated() {
                group.addTask {
                    if index % 32 == 0 {
                        Log.pipeline.debug("Downsampling frame \(index)/\(frames.count)")
                    }
                    return try self.vImageProcessor.downsample(
                        rgbaData: frame,
                        fromSize: self.sourceSize,
                        toSize: self.targetSize
                    )
                }
            }

            var results = [Data]()
            for try await downsampledFrame in group {
                results.append(downsampledFrame)
            }
            return results
        }
    }

    private func encodeCBORFrames(_ frames: [Data]) async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionPath = documentsPath.appendingPathComponent("cbor_frames/session_\(Date().timeIntervalSince1970)")
        try FileManager.default.createDirectory(at: sessionPath, withIntermediateDirectories: true)

        for (index, frame) in frames.enumerated() {
            if index % 32 == 0 {
                progress = Double(index) / Double(frames.count)
            }

            let cborData = try cborEncoder.encodeFrame(
                data: frame,
                index: index,
                width: targetSize,
                height: targetSize
            )

            let filePath = sessionPath.appendingPathComponent("frame_\(String(format: "%03d", index)).cbor")
            try cborData.write(to: filePath)
        }

        Log.pipeline.info("Saved CBOR frames to: \(sessionPath.path)")
    }

    // MARK: - Processing Paths

    private func processWithRust(_ frames: [Data]) async throws -> Data {
        let rustSignpost = PipelineSignpost.begin(.rustFFI)
        defer { PipelineSignpost.end(.rustFFI, rustSignpost) }

        // Prepare contiguous buffer
        let bufferSize = targetSize * targetSize * frames.count * 4
        var contiguousBuffer = Data(capacity: bufferSize)
        for frame in frames {
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
            width: UInt16(targetSize),
            height: UInt16(targetSize),
            frameCount: UInt16(frames.count),
            fps: 25,
            loopCount: 0,  // infinite
            optimize: true,
            includeTensor: false
        )

        let result = try processAllFrames(
            framesRgba: contiguousBuffer,
            width: UInt32(targetSize),
            height: UInt32(targetSize),
            frameCount: UInt32(frames.count),
            quantizeOpts: quantizeOpts,
            gifOpts: gifOpts
        )

        Log.ffi.info("Rust processed: \(result.finalFileSize) bytes in \(result.processingTimeMs)ms")
        return result.gifData
    }

    private func processWithSwift(_ frames: [Data]) async throws -> Data {
        let swiftSignpost = PipelineSignpost.begin(.swiftGIF)
        defer { PipelineSignpost.end(.swiftGIF, swiftSignpost) }

        let encoder = SwiftGIF89aEncoder()
        let config = SwiftGIF89aEncoder.Config(
            width: targetSize,
            height: targetSize,
            colorCount: 256,
            frameDelay: 0.04,  // 25fps
            loopCount: 0  // infinite
        )

        return try await encoder.encode(frames: frames, config: config)
    }
}

