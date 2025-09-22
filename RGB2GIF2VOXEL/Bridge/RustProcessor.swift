import Foundation
import Combine

// Import the generated UniFFI bindings - assuming they're in the same module
// If they're in a separate module, use: import rgb2gif_processor

/// Swift wrapper for the Rust RGB→GIF processor
/// Provides high-level interface to libimagequant + gif crate pipeline
@MainActor
public class RustProcessor: ObservableObject {

    // MARK: - Published Properties
    @Published public private(set) var isProcessing = false
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var currentPhase: ProcessingPhase = .idle
    @Published public private(set) var errorMessage: String?

    // MARK: - Processing Phases
    public enum ProcessingPhase: String, CaseIterable {
        case idle = "Ready"
        case capturing = "Capturing frames"
        case quantizing = "Color quantization"
        case encoding = "GIF encoding"
        case buildingTensor = "Building tensor"
        case saving = "Saving output"
        case complete = "Complete"
        case error = "Error"
    }

    // MARK: - Configuration
    private var quantizeOpts: QuantizeOpts
    private var gifOpts: GifOpts

    public init() {
        // Default options matching new API
        self.quantizeOpts = QuantizeOpts(
            qualityMin: 70,
            qualityMax: 100,
            speed: 5, // Balanced speed/quality
            paletteSize: 256,
            ditheringLevel: 1.0,
            sharedPalette: true
        )

        self.gifOpts = GifOpts(
            width: 256,
            height: 256,
            frameCount: 256,
            fps: 30,
            loopCount: 0, // Infinite
            optimize: true,
            includeTensor: false // NEW field
        )
    }

    // MARK: - Configuration Methods

    /// Configure quantization speed/quality trade-off
    /// - Parameter speed: 1 = best quality, 10 = fastest
    public func setQuantizationSpeed(_ speed: Int32) {
        quantizeOpts.speed = max(1, min(10, speed))
    }

    /// Configure output dimensions
    public func setDimensions(width: UInt16, height: UInt16) {
        gifOpts.width = width
        gifOpts.height = height
    }

    /// Configure frame rate
    public func setFrameRate(_ fps: UInt16) {
        gifOpts.fps = fps
    }

    /// Configure tensor generation
    public func setIncludeTensor(_ include: Bool) {
        gifOpts.includeTensor = include
    }

    // MARK: - Main Processing Function

    /// Process RGBA frames to GIF using single FFI call
    /// - Parameters:
    ///   - frames: Array of RGBA pixel data (4 bytes per pixel)
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    /// - Returns: ProcessResult containing GIF data and optional tensor
    public func processFramesToGIF(
        frames: [Data],
        width: Int,
        height: Int
    ) async -> ProcessResult? {

        await MainActor.run {
            self.isProcessing = true
            self.currentPhase = .quantizing
            self.progress = 0.0
            self.errorMessage = nil
        }

        do {
            // Flatten frames into single contiguous buffer
            var rgbaBuffer = Data()
            for frame in frames {
                rgbaBuffer.append(frame)
            }

            // Update options with actual dimensions
            gifOpts.width = UInt16(width)
            gifOpts.height = UInt16(height)
            gifOpts.frameCount = UInt16(frames.count)

            // Call new single FFI function on background thread
            let result = try await Task.detached(priority: .userInitiated) { [quantizeOpts = self.quantizeOpts, gifOpts = self.gifOpts] in
                try processAllFrames(
                    framesRgba: rgbaBuffer,
                    width: UInt32(width),
                    height: UInt32(height),
                    frameCount: UInt32(frames.count),
                    quantizeOpts: quantizeOpts,
                    gifOpts: gifOpts
                )
            }.value

            await MainActor.run {
                self.currentPhase = .complete
                self.progress = 1.0
                self.isProcessing = false
            }

            return result

        } catch let error as ProcessorError {
            await MainActor.run {
                self.currentPhase = .error
                self.errorMessage = error.localizedDescription
                self.isProcessing = false
            }
            return nil
        } catch {
            await MainActor.run {
                self.currentPhase = .error
                self.errorMessage = "Unknown error: \(error)"
                self.isProcessing = false
            }
            return nil
        }
    }

    // MARK: - Simplified Processing

    /// Process with tensor generation enabled
    /// The new API handles both GIF and tensor generation in a single call
    public func processWithTensor(
        frames: [Data],
        width: Int,
        height: Int
    ) async -> (gif: Data?, tensor: Data?) {

        // Enable tensor generation
        gifOpts.includeTensor = true

        // Process frames
        if let result = await processFramesToGIF(frames: frames, width: width, height: height) {
            return (gif: result.gifData, tensor: result.tensorData)
        }

        return (nil, nil)
    }

    /// Convenience method for just getting GIF data
    public func getGIFData(from result: ProcessResult) -> Data {
        return result.gifData
    }

    /// Convenience method for getting processing metrics
    public func getMetrics(from result: ProcessResult) -> (time: Float, paletteSize: UInt16, fileSize: UInt32) {
        return (
            time: result.processingTimeMs,
            paletteSize: result.paletteSizeUsed,
            fileSize: result.finalFileSize
        )
    }

    // MARK: - Progress Simulation

    /// Simulate progress for long-running operations
    /// (Real progress would come from Rust callbacks in future)
    private func simulateProgress(duration: TimeInterval) async {
        let steps = 20
        let stepDuration = duration / Double(steps)

        for i in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            await MainActor.run {
                self.progress = Double(i) / Double(steps)
            }
        }
    }
}