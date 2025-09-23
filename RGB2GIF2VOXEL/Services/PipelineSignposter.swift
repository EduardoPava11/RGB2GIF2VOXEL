//
//  PipelineSignposter.swift
//  RGB2GIF2VOXEL
//
//  Phase 7: OSSignposter instrumentation for pipeline phases
//

import Foundation
import os.signpost

/// Pipeline performance instrumentation with OSSignposter
@MainActor
public class PipelineSignposter {

    // MARK: - Signpost Log

    private static let subsystem = "com.yingif.rgb2gif2voxel.pipeline"
    private let signpostLog = OSLog(subsystem: subsystem, category: .pointsOfInterest)
    private let signposter: OSSignposter

    // MARK: - Signpost States

    private var captureState: OSSignpostIntervalState?
    private var downsampleState: OSSignpostIntervalState?
    private var cborEncodeState: OSSignpostIntervalState?
    private var rustFFIState: OSSignpostIntervalState?
    private var gifEncodeState: OSSignpostIntervalState?
    private var photosSaveState: OSSignpostIntervalState?
    private var tensorProcessState: OSSignpostIntervalState?
    private var voxelRenderState: OSSignpostIntervalState?

    // MARK: - Shared Instance

    public static let shared = PipelineSignposter()

    // MARK: - Init

    public init() {
        self.signposter = OSSignposter(subsystem: Self.subsystem, category: .pointsOfInterest)
    }

    // MARK: - Capture Phase

    public func beginCapture(frameCount: Int) {
        captureState = signposter.beginInterval("Capture", id: .exclusive, "Starting capture of \(frameCount) frames")
    }

    public func endCapture(capturedCount: Int) {
        if let state = captureState {
            signposter.endInterval("Capture", state, "Captured \(capturedCount) frames")
            captureState = nil
        }
    }

    // MARK: - Downsample Phase

    public func beginDownsample(fromSize: CGSize, toSize: CGSize) {
        downsampleState = signposter.beginInterval("Downsample", id: .exclusive,
                                  "Downsampling from \(Int(fromSize.width))x\(Int(fromSize.height)) to \(Int(toSize.width))x\(Int(toSize.height))")
    }

    public func endDownsample() {
        if let state = downsampleState {
            signposter.endInterval("Downsample", state)
            downsampleState = nil
        }
    }

    // MARK: - CBOR Encode Phase

    public func beginCBOREncode(frameCount: Int) {
        cborEncodeState = signposter.beginInterval("CBOREncode", id: .exclusive, "Encoding \(frameCount) frames to CBOR")
    }

    public func endCBOREncode(dataSize: Int) {
        if let state = cborEncodeState {
            signposter.endInterval("CBOREncode", state, "CBOR size: \(dataSize) bytes")
            cborEncodeState = nil
        }
    }

    // MARK: - Rust FFI Phase

    public func beginRustFFI(includeTensor: Bool) {
        rustFFIState = signposter.beginInterval("RustFFI", id: .exclusive, "Calling Rust FFI (tensor: \(includeTensor))")
    }

    public func endRustFFI(gifSize: Int, tensorSize: Int?) {
        if let state = rustFFIState {
            let tensorInfo = tensorSize.map { ", tensor: \($0) bytes" } ?? ""
            signposter.endInterval("RustFFI", state, "GIF: \(gifSize) bytes\(tensorInfo)")
            rustFFIState = nil
        }
    }

    // MARK: - GIF Encode Phase (Swift)

    public func beginGIFEncode(frameCount: Int) {
        gifEncodeState = signposter.beginInterval("GIFEncode", id: .exclusive, "Encoding \(frameCount) frames to GIF")
    }

    public func endGIFEncode(dataSize: Int) {
        if let state = gifEncodeState {
            signposter.endInterval("GIFEncode", state, "GIF size: \(dataSize) bytes")
            gifEncodeState = nil
        }
    }

    // MARK: - Photos Save Phase

    public func beginPhotosSave() {
        photosSaveState = signposter.beginInterval("PhotosSave", id: .exclusive, "Saving GIF to Photos")
    }

    public func endPhotosSave(success: Bool, assetID: String?) {
        if let state = photosSaveState {
            let status = success ? "Success" : "Failed"
            let idInfo = assetID.map { " ID: \($0)" } ?? ""
            signposter.endInterval("PhotosSave", state, "\(status)\(idInfo)")
            photosSaveState = nil
        }
    }

    // MARK: - Tensor Processing Phase

    public func beginTensorProcess(dataSize: Int) {
        tensorProcessState = signposter.beginInterval("TensorProcess", id: .exclusive, "Processing tensor: \(dataSize) bytes")
    }

    public func endTensorProcess(voxelCount: Int) {
        if let state = tensorProcessState {
            signposter.endInterval("TensorProcess", state, "Generated \(voxelCount) voxels")
            tensorProcessState = nil
        }
    }

    // MARK: - Voxel Rendering Phase

    public func beginVoxelRender(mode: String) {
        voxelRenderState = signposter.beginInterval("VoxelRender", id: .exclusive, "Rendering mode: \(mode)")
    }

    public func endVoxelRender(pointCount: Int) {
        if let state = voxelRenderState {
            signposter.endInterval("VoxelRender", state, "Rendered \(pointCount) points")
            voxelRenderState = nil
        }
    }

    // MARK: - Event Signposts (no duration)

    public func frameProcessed(_ index: Int) {
        signposter.emitEvent("FrameProcessed", "Frame \(index)")
    }

    public func memoryWarning() {
        signposter.emitEvent("MemoryWarning", "⚠️ Memory pressure detected")
    }

    public func error(_ message: String) {
        signposter.emitEvent("Error", "❌ \(message)")
    }

    // MARK: - Performance Report

    public func generateTimingReport() -> String {
        """
        📊 Pipeline Performance Report (View in Instruments → Points of Interest)

        Phases instrumented:
        • Capture: Frame capture from camera
        • Downsample: Image resizing
        • CBOREncode: CBOR serialization
        • RustFFI: Rust processing (GIF + tensor)
        • GIFEncode: Swift GIF encoding
        • PhotosSave: Saving to Photos library
        • TensorProcess: Tensor to voxel conversion
        • VoxelRender: 3D voxel rendering

        To view timings:
        1. Open Instruments
        2. Choose "Time Profiler" template
        3. Add "Points of Interest" instrument
        4. Filter by subsystem: \(PipelineSignposter.subsystem)
        5. Run the app and process frames
        6. View timeline and statistics
        """
    }
}

// MARK: - Integration Helper

extension PipelineSignposter {

    /// Convenience method to instrument a complete pipeline run
    public func instrumentPipelineRun<T>(_ operation: () async throws -> T) async rethrows -> T {
        let startTime = Date()

        do {
            let result = try await operation()

            let duration = Date().timeIntervalSince(startTime)
            signposter.emitEvent("PipelineComplete", "✅ Total time: \(String(format: "%.2f", duration))s")

            return result
        } catch {
            self.error("Pipeline failed: \(error.localizedDescription)")
            throw error
        }
    }
}