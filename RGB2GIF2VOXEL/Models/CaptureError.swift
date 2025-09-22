import Foundation

/// Comprehensive error handling for the capture pipeline
public enum CaptureError: LocalizedError, Equatable {

    // Camera errors
    case cameraUnavailable
    case cameraAccessDenied
    case cameraConfigurationFailed(String)
    case noSquareFormatAvailable

    // Processing errors
    case frameProcessingFailed(String)
    case rustFFIFailed(code: Int)
    case downsizeFailed
    case quantizationFailed
    case insufficientMemory

    // Capture errors
    case captureNotStarted
    case captureAlreadyInProgress
    case captureIncomplete(captured: Int, needed: Int)
    case frameDropped(reason: String)

    // Tensor errors
    case tensorBuildFailed
    case invalidTensorDimensions
    case emptyFrameBuffer

    // GIF errors
    case gifEncodingFailed(String)
    case gifBufferTooSmall
    case invalidPaletteSize

    // File errors
    case fileWriteFailed(URL)
    case fileReadFailed(URL)
    case directoryCreationFailed

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device"
        case .cameraAccessDenied:
            return "Camera access denied. Please enable in Settings"
        case .cameraConfigurationFailed(let reason):
            return "Camera configuration failed: \(reason)"
        case .noSquareFormatAvailable:
            return "No square camera format available"

        case .frameProcessingFailed(let reason):
            return "Frame processing failed: \(reason)"
        case .rustFFIFailed(let code):
            return "Rust processing failed with code: \(code)"
        case .downsizeFailed:
            return "Image downsize operation failed"
        case .quantizationFailed:
            return "Color quantization failed"
        case .insufficientMemory:
            return "Insufficient memory for operation"

        case .captureNotStarted:
            return "Capture has not been started"
        case .captureAlreadyInProgress:
            return "Capture is already in progress"
        case .captureIncomplete(let captured, let needed):
            return "Capture incomplete: \(captured)/\(needed) frames"
        case .frameDropped(let reason):
            return "Frame dropped: \(reason)"

        case .tensorBuildFailed:
            return "Failed to build cube tensor"
        case .invalidTensorDimensions:
            return "Invalid tensor dimensions"
        case .emptyFrameBuffer:
            return "No frames captured"

        case .gifEncodingFailed(let reason):
            return "GIF encoding failed: \(reason)"
        case .gifBufferTooSmall:
            return "GIF buffer too small"
        case .invalidPaletteSize:
            return "Invalid palette size (must be 2-256)"

        case .fileWriteFailed(let url):
            return "Failed to write file: \(url.lastPathComponent)"
        case .fileReadFailed(let url):
            return "Failed to read file: \(url.lastPathComponent)"
        case .directoryCreationFailed:
            return "Failed to create directory"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cameraAccessDenied:
            return "Go to Settings > RGB2GIF2VOXEL > Camera and enable access"
        case .insufficientMemory:
            return "Try using a smaller cube size or close other apps"
        case .captureIncomplete:
            return "Ensure capture completes before processing"
        case .invalidPaletteSize:
            return "Use 64, 128, or 256 colors"
        default:
            return nil
        }
    }
}