import Foundation
import AVFoundation

/// Complete capture configuration for the app
public struct CaptureConfiguration {

    // MARK: - Cube Sizes

    /// Available cube dimensions for N×N×N tensors
    public static let availableCubeSizes = [528, 264, 132]

    /// Default cube size
    public static let defaultCubeSize = 132

    /// Get memory requirement in MB for a cube size
    public static func memoryInMB(for cubeSize: Int) -> Double {
        let bytes = cubeSize * cubeSize * cubeSize
        return Double(bytes) / (1024.0 * 1024.0)
    }

    /// Get display label for cube size
    public static func label(for cubeSize: Int) -> String {
        let mb = memoryInMB(for: cubeSize)
        return String(format: "%d³ (%.1f MB)", cubeSize, mb)
    }

    // MARK: - Palette Sizes

    /// Available palette sizes for color quantization
    public static let availablePaletteSizes = [64, 128, 256]

    /// Default palette size
    public static let defaultPaletteSize = 256

    /// Get compression ratio estimate
    public static func compressionRatio(for paletteSize: Int) -> String {
        switch paletteSize {
        case 64:
            return "~10:1"
        case 128:
            return "~8:1"
        case 256:
            return "~6:1"
        default:
            return "N/A"
        }
    }

    // MARK: - GIF Settings

    /// Default frame delay in milliseconds
    public static let defaultFrameDelayMs = 40 // 25 FPS

    /// Available frame delays
    public static let availableFrameDelays = [20, 40, 60, 80, 100] // 50fps to 10fps

    // MARK: - Camera Settings

    /// Preferred camera position
    public static let preferredCameraPosition = AVCaptureDevice.Position.front

    /// Prefer TrueDepth camera if available
    public static let preferTrueDepth = true

    /// Video orientation
    public static let videoOrientation = AVCaptureVideoOrientation.portrait

    /// Mirror front camera
    public static let mirrorFrontCamera = true

    // MARK: - Processing Settings

    /// Maximum concurrent frame processing
    public static let maxConcurrentFrames = 2

    /// Frame processing quality
    public static let processingQuality = DispatchQoS.QoSClass.userInitiated

    /// Enable frame dropping for performance
    public static let allowFrameDropping = false // Deterministic capture

    // MARK: - UI Settings

    /// Show FPS counter
    public static let showFPSCounter = true

    /// Show memory usage
    public static let showMemoryUsage = false

    /// Auto-navigate to gallery after capture
    public static let autoNavigateToGallery = false

    // MARK: - File Management

    /// Save captured tensors to documents
    public static let saveTensorsToDocuments = false

    /// Tensor file extension
    public static let tensorFileExtension = "cube"

    /// GIF file prefix
    public static let gifFilePrefix = "cube_"

    // MARK: - Debug Settings

    /// Enable debug logging
    public static let enableDebugLogging = false

    /// Save intermediate frames
    public static let saveIntermediateFrames = false
}