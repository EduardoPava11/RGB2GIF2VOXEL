import Foundation
import AVFoundation
import Combine
import CoreMedia
import CoreVideo

/// Controller for capturing exactly N frames to form an N×N×N cube tensor
@MainActor
public class CubeClipController: ObservableObject {

    // MARK: - Published State
    @Published public private(set) var framesCaptured: Int = 0
    @Published public private(set) var isCapturing: Bool = false
    @Published public private(set) var captureComplete: Bool = false

    // MARK: - Configuration
    public let sideN: Int
    public let paletteSize: Int
    private let determinismSeed: UInt64 = 0x1337BEEF // Fixed seed for determinism

    // MARK: - Frame Tracking
    private var capturedFrames: [QuantizedFrame] = []
    private var firstFrameTime: CMTime?
    private var lastAcceptedTimestamp: CMTime?  // For duplicate/out-of-order detection
    private let frameStride: Int // For uniform sampling if needed

    // MARK: - Initialization
    public init(sideN: Int, paletteSize: Int = 256) {
        self.sideN = sideN
        self.paletteSize = paletteSize
        self.frameStride = 1 // Accept every frame for now (can adjust for high FPS)
        self.capturedFrames.reserveCapacity(sideN)
    }

    // MARK: - Computed Properties
    public var framesNeeded: Int {
        return sideN
    }

    // MARK: - Capture Control
    public func startCapture() {
        guard !isCapturing else { return }

        framesCaptured = 0
        captureComplete = false
        capturedFrames.removeAll()
        firstFrameTime = nil
        lastAcceptedTimestamp = nil  // Reset timestamp tracking
        isCapturing = true
    }

    public func stopCapture() {
        isCapturing = false
        captureComplete = framesCaptured >= framesNeeded
    }

    // MARK: - Frame Acceptance Logic
    /// Determines if we should accept the next frame (uniform sampling)
    public func shouldAcceptNextFrame(timestamp: CMTime) -> Bool {
        guard isCapturing else { return false }
        guard framesCaptured < framesNeeded else {
            // Auto-stop when we have enough frames
            stopCapture()
            return false
        }

        // Check for duplicate or out-of-order frames
        // Critical when alwaysDiscardsLateVideoFrames = true
        if let lastTimestamp = lastAcceptedTimestamp {
            // CMTime comparison: ensure strictly increasing timestamps
            guard timestamp > lastTimestamp else {
                print("⚠️ Dropped frame: timestamp \(timestamp.seconds) <= last \(lastTimestamp.seconds)")
                return false
            }
        }

        // Store first frame time for reference
        if firstFrameTime == nil {
            firstFrameTime = timestamp
        }

        // Update last accepted timestamp
        lastAcceptedTimestamp = timestamp

        // Simple deterministic acceptance: every Nth frame
        // For more sophisticated uniform sampling over time window,
        // we could compute frame intervals
        return true // Accept all frames until we hit N
    }

    // MARK: - Frame Ingestion
    /// Process and store a captured frame
    /// - Returns: true if this was the final frame needed
    public func ingestFrame(_ quantizedFrame: QuantizedFrame) -> Bool {
        guard isCapturing else { return false }

        capturedFrames.append(quantizedFrame)
        framesCaptured += 1

        // Check if we've reached our target
        if framesCaptured >= framesNeeded {
            stopCapture()
            return true
        }

        return false
    }

    // MARK: - Cube Tensor Export
    /// Build the final N×N×N cube tensor from captured frames
    public func buildCubeTensor() -> CubeTensor? {
        guard captureComplete else { return nil }
        guard capturedFrames.count == framesNeeded else { return nil }

        return CubeTensor(
            frames: capturedFrames,
            sideN: sideN,
            paletteSize: paletteSize
        )
    }

    // MARK: - Progress
    public var captureProgress: Double {
        guard framesNeeded > 0 else { return 0 }
        return Double(framesCaptured) / Double(framesNeeded)
    }

    public var progressText: String {
        return "\(framesCaptured)/\(framesNeeded)"
    }
}