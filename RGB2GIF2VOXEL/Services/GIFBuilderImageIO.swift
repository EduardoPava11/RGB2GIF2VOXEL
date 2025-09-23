//
//  GIFBuilderImageIO.swift
//  RGB2GIF2VOXEL
//
//  Reliable GIF89a encoder using ImageIO framework
//

import Foundation
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers
import CoreGraphics
import UIKit

/// Reliable GIF builder using ImageIO
public class GIFBuilderImageIO {

    // MARK: - Configuration

    public struct Config {
        let width: Int
        let height: Int
        let fps: Int
        let loopCount: Int  // 0 = infinite
        let quality: Float  // 0.0 to 1.0

        public init(
            width: Int = 256,
            height: Int = 256,
            fps: Int = 30,
            loopCount: Int = 0,
            quality: Float = 0.9
        ) {
            self.width = width
            self.height = height
            self.fps = fps
            self.loopCount = loopCount
            self.quality = quality
        }
    }

    // MARK: - Build GIF from RGBA Data

    public func buildGIF(
        frames: [Data],
        config: Config
    ) -> Data? {
        print("🎬 Building GIF with ImageIO...")
        print("   Frames: \(frames.count)")
        print("   Size: \(config.width)×\(config.height)")
        print("   FPS: \(config.fps)")

        // Create destination
        let gifData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            gifData as CFMutableData,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            print("❌ Failed to create CGImageDestination")
            return nil
        }

        // Set GIF properties
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: config.loopCount,
                kCGImagePropertyGIFHasGlobalColorMap: true
            ] as [CFString: Any]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Frame delay
        let frameDelay = 1.0 / Double(config.fps)

        // Add each frame
        for (index, frameData) in frames.enumerated() {
            autoreleasepool {
                guard let cgImage = createCGImage(
                    from: frameData,
                    width: config.width,
                    height: config.height
                ) else {
                    print("⚠️ Skipping frame \(index) - failed to create CGImage")
                    return
                }

                // Frame properties
                let frameProperties: [CFString: Any] = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: frameDelay,
                        kCGImagePropertyGIFUnclampedDelayTime: frameDelay
                    ] as [CFString: Any]
                ]

                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }

            // Progress update
            if index % 10 == 0 {
                print("   Processing frame \(index + 1)/\(frames.count)...")
            }
        }

        // Finalize
        guard CGImageDestinationFinalize(destination) else {
            print("❌ Failed to finalize GIF")
            return nil
        }

        print("✅ GIF created successfully: \(gifData.length) bytes")
        return gifData as Data
    }

    // MARK: - Build GIF from UIImages

    public func buildGIF(
        images: [UIImage],
        config: Config
    ) -> Data? {
        print("🎬 Building GIF from UIImages...")

        let gifData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            gifData as CFMutableData,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ) else {
            print("❌ Failed to create CGImageDestination")
            return nil
        }

        // GIF properties
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: config.loopCount
            ] as [CFString: Any]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameDelay = 1.0 / Double(config.fps)

        // Add frames
        for (index, image) in images.enumerated() {
            guard let cgImage = image.cgImage else {
                print("⚠️ Skipping frame \(index) - no CGImage")
                continue
            }

            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay
                ] as [CFString: Any]
            ]

            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            print("❌ Failed to finalize GIF")
            return nil
        }

        print("✅ GIF created: \(gifData.length) bytes")
        return gifData as Data
    }

    // MARK: - Create CGImage from RGBA Data

    private func createCGImage(from data: Data, width: Int, height: Int) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8

        guard data.count >= width * height * bytesPerPixel else {
            print("❌ Invalid data size for \(width)×\(height) image")
            return nil
        }

        // Create bitmap context
        guard let context = data.withUnsafeBytes({ bytes -> CGContext? in
            guard let baseAddress = bytes.baseAddress else { return nil }

            return CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue  // BGRA format
            )
        }) else {
            print("❌ Failed to create CGContext")
            return nil
        }

        return context.makeImage()
    }

    // MARK: - Optimize GIF (reduce size)

    public func optimizeGIF(_ gifData: Data, targetSize: Int? = nil) -> Data? {
        print("🔧 Optimizing GIF...")
        print("   Original size: \(gifData.count) bytes")

        // For now, return original
        // TODO: Implement optimization with color reduction, frame dropping, etc.
        return gifData
    }
}

// MARK: - Usage Example

/*
 let builder = GIFBuilderImageIO()

 let config = GIFBuilderImageIO.Config(
     width: 256,
     height: 256,
     fps: 30,
     loopCount: 0,
     quality: 0.9
 )

 // From RGBA data frames
 if let gifData = builder.buildGIF(frames: rgbaFrames, config: config) {
     // Save or share gifData
 }

 // From UIImages
 if let gifData = builder.buildGIF(images: uiImages, config: config) {
     // Save or share gifData
 }
 */