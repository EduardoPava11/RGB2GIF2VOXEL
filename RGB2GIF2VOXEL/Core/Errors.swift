//
//  Errors.swift
//  RGB2GIF2VOXEL
//
//  Unified error definitions for the entire app
//

import Foundation
import Accelerate

// MARK: - Pipeline Errors

public enum PipelineError: LocalizedError {
    case permissionDenied(String)
    case sessionSetupFailed(String)
    case captureInterrupted
    case processingFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .sessionSetupFailed(let reason):
            return "Camera setup failed: \(reason)"
        case .captureInterrupted:
            return "Capture was interrupted"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

// MARK: - Downsampling Errors

public enum DownsampleError: LocalizedError {
    case invalidPixelBuffer
    case invalidData
    case invalidDataSize(expected: Int, actual: Int)
    case vImageError(vImage_Error)
    case scalingFailed(vImage_Error)
    case unsupportedPixelFormat

    public var errorDescription: String? {
        switch self {
        case .invalidPixelBuffer:
            return "Invalid pixel buffer"
        case .invalidData:
            return "Invalid data"
        case .invalidDataSize(let expected, let actual):
            return "Invalid data size: expected \(expected), got \(actual)"
        case .vImageError(let error):
            return "vImage error: \(error)"
        case .scalingFailed(let error):
            return "Scaling failed with error: \(error)"
        case .unsupportedPixelFormat:
            return "Unsupported pixel format"
        }
    }
}

// MARK: - FFI Errors

public enum FFIError: LocalizedError {
    case rustProcessingFailed(Int32)
    case zigCBORFailed(String)
    case invalidBuffer
    case invalidResult

    public var errorDescription: String? {
        switch self {
        case .rustProcessingFailed(let code):
            return "Rust processing failed with code: \(code)"
        case .zigCBORFailed(let reason):
            return "Zig CBOR failed: \(reason)"
        case .invalidBuffer:
            return "Invalid buffer passed to FFI"
        case .invalidResult:
            return "Invalid result from FFI"
        }
    }
}

// MARK: - Storage Errors

public enum StorageError: LocalizedError {
    case fileNotFound(URL)
    case writeFailed(URL, Error)
    case readFailed(URL, Error)
    case invalidFormat
    case insufficientSpace

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .writeFailed(let url, let error):
            return "Failed to write \(url.lastPathComponent): \(error.localizedDescription)"
        case .readFailed(let url, let error):
            return "Failed to read \(url.lastPathComponent): \(error.localizedDescription)"
        case .invalidFormat:
            return "Invalid file format"
        case .insufficientSpace:
            return "Insufficient storage space"
        }
    }
}

// MARK: - Camera Errors

public enum CameraError: LocalizedError {
    case noDeviceFound
    case sessionConfigurationFailed
    case noValidFormat
    case deviceLockFailed

    public var errorDescription: String? {
        switch self {
        case .noDeviceFound:
            return "No camera device found"
        case .sessionConfigurationFailed:
            return "Failed to configure camera session"
        case .noValidFormat:
            return "No valid camera format found"
        case .deviceLockFailed:
            return "Failed to lock camera device for configuration"
        }
    }
}

// MARK: - Processing Errors

public enum ProcessingError: LocalizedError {
    case downsamplingFailed(DownsampleError)
    case quantizationFailed(String)
    case encodingFailed(String)
    case memoryPressure
    case ffiError(code: Int32)
    case invalidInput
    case gifEncodingFailed(code: Int32)

    public var errorDescription: String? {
        switch self {
        case .downsamplingFailed(let error):
            return "Downsampling failed: \(error.localizedDescription)"
        case .quantizationFailed(let reason):
            return "Quantization failed: \(reason)"
        case .encodingFailed(let reason):
            return "Encoding failed: \(reason)"
        case .memoryPressure:
            return "Memory pressure detected"
        case .ffiError(let code):
            return "FFI processing failed with code: \(code)"
        case .invalidInput:
            return "Invalid input data"
        case .gifEncodingFailed(let code):
            return "GIF encoding failed with code: \(code)"
        }
    }
}