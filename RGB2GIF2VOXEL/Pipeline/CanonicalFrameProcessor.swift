//
//  CanonicalFrameProcessor.swift
//  RGB2GIF2VOXEL
//
//  Single source of truth for frame processing
//  Produces exactly 128x128x4 BGRA buffers with no stride/padding
//

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import Accelerate
import UIKit
import os

/// Canonical frame processor that produces consistent 128x128x4 BGRA buffers
public final class CanonicalFrameProcessor {

    // MARK: - Constants

    public static let frameSize = 128
    public static let bytesPerPixel = 4
    public static let bytesPerFrame = frameSize * frameSize * bytesPerPixel // 65,536 bytes exactly

    private let logger = Logger(subsystem: "com.rgb2gif2voxel", category: "CanonicalProcessor")

    // MARK: - Public Methods

    /// Process a CVPixelBuffer into exactly 128x128x4 BGRA data
    /// Handles stride, padding, cropping, and downsampling correctly
    public func processFrame(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            logger.error("Failed to get pixel buffer base address")
            return nil
        }

        // Get actual dimensions and stride
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        logger.debug("Input: \(width)x\(height), stride: \(bytesPerRow)")

        // Step 1: Extract square region from center (maintaining stride)
        let squareSize = min(width, height)
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        // Create vImage buffers for source (with proper stride)
        var sourceBuffer = vImage_Buffer(
            data: baseAddress.advanced(by: yOffset * bytesPerRow + xOffset * Self.bytesPerPixel),
            height: vImagePixelCount(squareSize),
            width: vImagePixelCount(squareSize),
            rowBytes: bytesPerRow  // Use actual stride!
        )

        // Step 2: Create destination buffer for 128x128 (no padding)
        let destRowBytes = Self.frameSize * Self.bytesPerPixel
        var destData = Data(count: Self.bytesPerFrame)

        var error: vImage_Error = kvImageNoError
        destData.withUnsafeMutableBytes { destPtr in
            var destBuffer = vImage_Buffer(
                data: destPtr.baseAddress,
                height: vImagePixelCount(Self.frameSize),
                width: vImagePixelCount(Self.frameSize),
                rowBytes: destRowBytes  // Exactly 128*4, no padding
            )

            // Step 3: Scale to exactly 128x128 using Lanczos
            error = vImageScale_ARGB8888(
                &sourceBuffer,
                &destBuffer,
                nil,  // Use default temporary buffer
                vImage_Flags(kvImageHighQualityResampling)
            )
        }

        guard error == kvImageNoError else {
            logger.error("vImage scaling failed: \(error)")
            return nil
        }

        // Step 4: Convert BGRA to RGBA if needed (iOS camera is BGRA)
        // For now, keep as BGRA since that's what iOS uses natively

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("Processed frame in \(String(format: "%.3f", processingTime))s")

        // Validate output size
        assert(destData.count == Self.bytesPerFrame, "Output must be exactly 65,536 bytes")

        return destData
    }

    /// Create a correctly-configured CGImage from 128x128x4 BGRA data
    public func createCGImage(from frameData: Data) -> CGImage? {
        guard frameData.count == Self.bytesPerFrame else {
            logger.error("Invalid frame data size: \(frameData.count), expected \(Self.bytesPerFrame)")
            return nil
        }

        // Create CGImage with correct BGRA configuration
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = Self.frameSize * Self.bytesPerPixel  // No padding

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            logger.error("Failed to create sRGB color space")
            return nil
        }

        // CRITICAL: For BGRA, use premultipliedFirst | byteOrder32Little
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let provider = CGDataProvider(data: frameData as CFData) else {
            logger.error("Failed to create data provider")
            return nil
        }

        return CGImage(
            width: Self.frameSize,
            height: Self.frameSize,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Create UIImage from frame data
    public func createUIImage(from frameData: Data) -> UIImage? {
        guard let cgImage = createCGImage(from: frameData) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Handle orientation and mirroring for camera position
    public func correctOrientation(
        _ frameData: Data,
        position: AVCaptureDevice.Position,
        orientation: UIDeviceOrientation
    ) -> Data? {

        guard let image = createUIImage(from: frameData) else { return nil }

        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: Self.frameSize, height: Self.frameSize),
            false,
            1.0
        )
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Handle front camera mirroring
        if position == .front {
            context.translateBy(x: CGFloat(Self.frameSize), y: 0)
            context.scaleBy(x: -1.0, y: 1.0)
        }

        // Handle device orientation
        switch orientation {
        case .landscapeLeft:
            context.translateBy(x: CGFloat(Self.frameSize) / 2, y: CGFloat(Self.frameSize) / 2)
            context.rotate(by: .pi / 2)
            context.translateBy(x: -CGFloat(Self.frameSize) / 2, y: -CGFloat(Self.frameSize) / 2)
        case .landscapeRight:
            context.translateBy(x: CGFloat(Self.frameSize) / 2, y: CGFloat(Self.frameSize) / 2)
            context.rotate(by: -.pi / 2)
            context.translateBy(x: -CGFloat(Self.frameSize) / 2, y: -CGFloat(Self.frameSize) / 2)
        case .portraitUpsideDown:
            context.translateBy(x: CGFloat(Self.frameSize) / 2, y: CGFloat(Self.frameSize) / 2)
            context.rotate(by: .pi)
            context.translateBy(x: -CGFloat(Self.frameSize) / 2, y: -CGFloat(Self.frameSize) / 2)
        default:
            break // Portrait is default
        }

        image.draw(in: CGRect(x: 0, y: 0, width: Self.frameSize, height: Self.frameSize))

        guard let correctedImage = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = correctedImage.cgImage else { return nil }

        // Extract pixel data from corrected image
        guard let context = CGContext(
            data: nil,
            width: Self.frameSize,
            height: Self.frameSize,
            bitsPerComponent: 8,
            bytesPerRow: Self.frameSize * Self.bytesPerPixel,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: Self.frameSize, height: Self.frameSize))

        guard let data = context.data else { return nil }
        return Data(bytes: data, count: Self.bytesPerFrame)
    }

    /// Build 128x128x128x4 tensor from frames
    public func buildTensor(from frames: [Data]) -> Data? {
        guard frames.count == Self.frameSize else {
            logger.error("Need exactly 128 frames, got \(frames.count)")
            return nil
        }

        // Validate all frames
        for (index, frame) in frames.enumerated() {
            guard frame.count == Self.bytesPerFrame else {
                logger.error("Frame \(index) has wrong size: \(frame.count)")
                return nil
            }
        }

        // Concatenate all frames into tensor
        var tensor = Data(capacity: Self.frameSize * Self.frameSize * Self.frameSize * Self.bytesPerPixel)
        for frame in frames {
            tensor.append(frame)
        }

        let expectedSize = Self.frameSize * Self.frameSize * Self.frameSize * Self.bytesPerPixel
        assert(tensor.count == expectedSize, "Tensor must be exactly \(expectedSize) bytes")

        logger.info("Built tensor: \(tensor.count) bytes (\(tensor.count / 1024 / 1024) MB)")
        return tensor
    }

    /// Save tensor to disk
    public func saveTensor(_ tensor: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxel_tensor_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("tensor")

        do {
            try tensor.write(to: url)
            logger.info("Saved tensor to: \(url.path)")
            return url
        } catch {
            logger.error("Failed to save tensor: \(error)")
            return nil
        }
    }
}