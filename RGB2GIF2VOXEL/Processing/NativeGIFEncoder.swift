//
//  NativeGIFEncoder.swift
//  RGB2GIF2VOXEL
//
//  Pure Swift GIF encoding using ImageIO framework
//  "Swift Path" - No Rust dependencies, reliable fallback
//

import Foundation
import Combine
import ImageIO
import CoreGraphics
import CoreVideo
import UniformTypeIdentifiers
import Photos

#if canImport(UIKit)
import UIKit
#endif

#if canImport(MobileCoreServices)
import MobileCoreServices
#endif

/// Pure Swift GIF encoder using native iOS ImageIO framework
/// This provides a reliable "Swift Path" that works without any Rust FFI dependencies
@MainActor
class NativeGIFEncoder: ObservableObject {
    
    // MARK: - Configuration
    
    struct Configuration {
        let frameDelay: TimeInterval
        let loopCount: Int
        let quality: Float
        let enableDithering: Bool
        let colorCount: Int
        
        init(frameDelay: TimeInterval = 0.1, loopCount: Int = 0, quality: Float = 0.8, enableDithering: Bool = true, colorCount: Int = 256) {
            self.frameDelay = frameDelay
            self.loopCount = loopCount
            self.quality = quality
            self.enableDithering = enableDithering
            self.colorCount = colorCount
        }
    }
    
    // MARK: - Progress Tracking
    
    @Published var isProcessing: Bool = false
    @Published var progress: Float = 0.0
    @Published var statusMessage: String = ""
    
    // MARK: - Error Types
    
    enum EncodingError: LocalizedError {
        case invalidInput
        case destinationCreationFailed
        case imageAdditionFailed
        case finalizationFailed
        case noFrames
        
        var errorDescription: String? {
            switch self {
            case .invalidInput: return "Invalid input data"
            case .destinationCreationFailed: return "Failed to create GIF destination"
            case .imageAdditionFailed: return "Failed to add frame to GIF"
            case .finalizationFailed: return "Failed to finalize GIF"
            case .noFrames: return "No frames to encode"
            }
        }
    }
    
    // MARK: - Main Encoding Function
    
    /// Encode frames to GIF using pure Swift/ImageIO
    /// - Parameters:
    ///   - frames: Array of CVPixelBuffer frames from camera
    ///   - config: Encoding configuration
    /// - Returns: GIF data ready for saving
    func encodeGIF(frames: [CVPixelBuffer], config: Configuration = Configuration()) async throws -> Data {
        guard !frames.isEmpty else {
            throw EncodingError.noFrames
        }
        
        await MainActor.run {
            isProcessing = true
            progress = 0.0
            statusMessage = "Starting Swift GIF encoding..."
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let gifData = try await performEncoding(frames: frames, config: config)
                    
                    await MainActor.run {
                        isProcessing = false
                        progress = 1.0
                        statusMessage = "Swift GIF encoding complete!"
                    }
                    
                    continuation.resume(returning: gifData)
                } catch {
                    await MainActor.run {
                        isProcessing = false
                        statusMessage = "Swift encoding failed: \(error.localizedDescription)"
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Core Encoding Logic
    
    private func performEncoding(frames: [CVPixelBuffer], config: Configuration) async throws -> Data {
        let mutableData = NSMutableData()
        
        // Create GIF destination
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw EncodingError.destinationCreationFailed
        }
        
        // Set global GIF properties
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: config.loopCount,
                kCGImagePropertyGIFHasGlobalColorMap: true
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        
        await updateProgress(0.1, "Processing frames...")
        
        // Process each frame
        for (index, pixelBuffer) in frames.enumerated() {
            // Convert CVPixelBuffer to CGImage
            guard let cgImage = createCGImage(from: pixelBuffer, quality: config.quality) else {
                throw EncodingError.imageAdditionFailed
            }
            
            // Frame properties
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: config.frameDelay,
                    kCGImagePropertyGIFUnclampedDelayTime: config.frameDelay
                ]
            ]
            
            // Add frame to GIF
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            
            // Update progress
            let progress = 0.1 + (0.8 * Float(index + 1) / Float(frames.count))
            await updateProgress(progress, "Processing frame \(index + 1)/\(frames.count)")
        }
        
        await updateProgress(0.9, "Finalizing GIF...")
        
        // Finalize the GIF
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.finalizationFailed
        }
        
        return mutableData as Data
    }
    
    // MARK: - Image Processing
    
    private func createCGImage(from pixelBuffer: CVPixelBuffer, quality: Float) -> CGImage? {
        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        // Create color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create bitmap context
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Create CGImage
        return context.makeImage()
    }
    
    // MARK: - Progress Updates
    
    private func updateProgress(_ progress: Float, _ message: String) async {
        await MainActor.run {
            self.progress = progress
            self.statusMessage = message
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Quick encode with default settings
    func quickEncodeGIF(frames: [CVPixelBuffer]) async throws -> Data {
        return try await encodeGIF(frames: frames, config: Configuration())
    }
    
    /// Encode with custom quality
    func encodeGIF(frames: [CVPixelBuffer], quality: Float, fps: Int = 10) async throws -> Data {
        let frameDelay = 1.0 / Double(fps)
        
        return try await encodeGIF(frames: frames, config: Configuration(
            frameDelay: frameDelay,
            loopCount: 0,
            quality: quality,
            enableDithering: true,
            colorCount: 256
        ))
    }
}

// MARK: - Static Utilities

extension NativeGIFEncoder {
    
    /// Save GIF data to Photos library
    static func saveToPhotos(_ gifData: Data) async throws {
        // Create temporary file
        let tempDirectory = FileManager.default.temporaryDirectory
        let temporaryURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("gif")
        
        do {
            try gifData.write(to: temporaryURL)
            
            // Save to Photos using Photos framework
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: temporaryURL)
            }
            print("GIF saved to Photos successfully")
            
            // Clean up after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            
        } catch {
            // Clean up on error
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }
    
    /// Estimate GIF file size
    static func estimateFileSize(frameCount: Int, width: Int, height: Int, quality: Float = 0.8) -> Int {
        let pixelsPerFrame = width * height
        let bytesPerFrame = Int(Float(pixelsPerFrame) * quality * 0.3) // Rough estimate
        return frameCount * bytesPerFrame
    }
}