//
//  GifVolumeLoader.swift
//  RGB2GIF2VOXEL
//
//  Metal 3D texture loader for GIF tensor visualization
//  Converts GIF frames into a 128×128×128 RGBA volume
//

import Foundation
import Combine
import Metal
import MetalKit
import ImageIO
import CoreGraphics
import simd

/// 3D volume representation for Metal rendering
public struct Volume3D {
    let texture: MTLTexture           // type3D or type2DArray
    let size: SIMD3<UInt32>          // (128, 128, 128)
    let frameDurations: [Float]       // Per-frame timing
    let totalDuration: Float          // Sum of all frame durations
    let checksum: UInt32              // Quick validation
}

/// GIF to Metal 3D texture converter
@MainActor
public class GifVolumeLoader: ObservableObject {

    // MARK: - Properties

    @Published public var isLoading = false
    @Published public var loadProgress: Float = 0.0
    @Published public var lastError: String?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // MARK: - Constants

    private static let volumeSize = 128
    private static let bytesPerPixel = 4  // RGBA8
    private static let totalBytes = volumeSize * volumeSize * volumeSize * bytesPerPixel  // 8,388,608

    // MARK: - Init

    public init(device: MTLDevice? = nil) {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        print("🎨 GifVolumeLoader initialized with Metal device: \(self.device.name)")
    }

    // MARK: - Load GIF to Volume

    /// Load GIF data and convert to Metal 3D texture
    public func loadGIFVolume(data: Data) async -> Volume3D? {
        isLoading = true
        loadProgress = 0.0
        lastError = nil

        defer {
            isLoading = false
        }

        // Phase 0: Parse GIF with ImageIO
        guard let frames = extractGIFFrames(from: data) else {
            lastError = "Failed to extract GIF frames"
            return nil
        }

        print("📦 Extracted \(frames.count) frames from GIF")
        loadProgress = 0.2

        // Phase 1: Build RGBA tensor (128×128×128×4)
        let tensorData = await buildTensorData(from: frames)
        loadProgress = 0.6

        // Phase 2: Create Metal 3D texture
        guard let texture = createMetal3DTexture(from: tensorData) else {
            lastError = "Failed to create Metal 3D texture"
            return nil
        }

        loadProgress = 0.9

        // Phase 3: Build volume descriptor
        let volume = Volume3D(
            texture: texture,
            size: SIMD3<UInt32>(UInt32(Self.volumeSize), UInt32(Self.volumeSize), UInt32(Self.volumeSize)),
            frameDurations: frames.map { $0.duration },
            totalDuration: frames.reduce(0) { $0 + $1.duration },
            checksum: computeChecksum(tensorData)
        )

        loadProgress = 1.0

        print("✅ Created Volume3D:")
        print("   Texture type: \(texture.textureType == .type3D ? "3D" : "2D Array")")
        print("   Size: \(volume.size)")
        print("   Frames: \(frames.count)")
        print("   Duration: \(volume.totalDuration)s")
        print("   Checksum: \(String(format: "0x%08X", volume.checksum))")
        print("   Memory: \(Self.totalBytes / 1_000_000) MB")

        return volume
    }

    // MARK: - Extract GIF Frames

    private struct GIFFrame {
        let cgImage: CGImage
        let duration: Float
    }

    private func extractGIFFrames(from data: Data) -> [GIFFrame]? {
        // Create image source from GIF data
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            print("❌ Failed to create image source from GIF data")
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            print("❌ GIF has no frames")
            return nil
        }

        var frames: [GIFFrame] = []

        for i in 0..<min(frameCount, Self.volumeSize) {
            // Extract frame image
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                print("⚠️ Skipping frame \(i) - couldn't extract")
                continue
            }

            // Extract frame duration
            let duration: Float
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
               let delayTime = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Float {
                duration = delayTime > 0 ? delayTime : 0.1
            } else {
                duration = 0.1  // Default 100ms
            }

            frames.append(GIFFrame(cgImage: cgImage, duration: duration))
        }

        // Pad to 128 frames if needed by repeating
        while frames.count < Self.volumeSize {
            if let lastFrame = frames.last {
                frames.append(lastFrame)
            } else {
                break
            }
        }

        return frames.isEmpty ? nil : Array(frames.prefix(Self.volumeSize))
    }

    // MARK: - Build Tensor Data

    private func buildTensorData(from frames: [GIFFrame]) async -> Data {
        var tensorData = Data(capacity: Self.totalBytes)

        for (z, frame) in frames.enumerated() {
            autoreleasepool {
                // Resize frame to 128×128 if needed
                let resized = resizeImage(frame.cgImage, to: CGSize(width: Self.volumeSize, height: Self.volumeSize))

                // Convert to RGBA data
                if let rgbaData = extractRGBAData(from: resized) {
                    tensorData.append(rgbaData)
                } else {
                    // Fallback: black frame
                    let blackFrame = Data(repeating: 0, count: Self.volumeSize * Self.volumeSize * Self.bytesPerPixel)
                    tensorData.append(blackFrame)
                }

                // Update progress
                let progress = Float(z) / Float(frames.count)
                Task { @MainActor in
                    self.loadProgress = 0.2 + (0.4 * progress)
                }
            }
        }

        // Ensure we have exactly the right size
        if tensorData.count < Self.totalBytes {
            // Pad with zeros
            let padding = Data(repeating: 0, count: Self.totalBytes - tensorData.count)
            tensorData.append(padding)
        } else if tensorData.count > Self.totalBytes {
            // Truncate
            tensorData = tensorData.prefix(Self.totalBytes)
        }

        print("📊 Built tensor data: \(tensorData.count) bytes (expected \(Self.totalBytes))")
        return tensorData
    }

    // MARK: - Image Processing

    private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // Draw scaled image
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage() ?? image
    }

    private func extractRGBAData(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4

        var data = Data(count: height * bytesPerRow)

        data.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return data
    }

    // MARK: - Create Metal 3D Texture

    private func createMetal3DTexture(from data: Data) -> MTLTexture? {
        // Try 3D texture first (preferred)
        if let texture3D = create3DTexture(from: data) {
            return texture3D
        }

        // Fallback to 2D array if 3D fails
        print("⚠️ 3D texture creation failed, falling back to 2D array")
        return create2DArrayTexture(from: data)
    }

    private func create3DTexture(from data: Data) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = Self.volumeSize
        descriptor.height = Self.volumeSize
        descriptor.depth = Self.volumeSize
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared  // CPU + GPU access

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("❌ Failed to create 3D texture")
            return nil
        }

        // Upload data to texture
        let bytesPerRow = Self.volumeSize * Self.bytesPerPixel
        let bytesPerImage = bytesPerRow * Self.volumeSize

        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }

            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: Self.volumeSize, height: Self.volumeSize, depth: Self.volumeSize)
                ),
                mipmapLevel: 0,
                slice: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }

        print("✅ Created 3D texture: \(Self.volumeSize)³")
        return texture
    }

    private func create2DArrayTexture(from data: Data) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = Self.volumeSize
        descriptor.height = Self.volumeSize
        descriptor.arrayLength = Self.volumeSize  // 128 layers
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("❌ Failed to create 2D array texture")
            return nil
        }

        // Upload each slice
        let bytesPerRow = Self.volumeSize * Self.bytesPerPixel
        let bytesPerSlice = bytesPerRow * Self.volumeSize

        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }

            for z in 0..<Self.volumeSize {
                let sliceOffset = z * bytesPerSlice
                let slicePtr = baseAddress.advanced(by: sliceOffset)

                texture.replace(
                    region: MTLRegion(
                        origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(width: Self.volumeSize, height: Self.volumeSize, depth: 1)
                    ),
                    mipmapLevel: 0,
                    slice: z,
                    withBytes: slicePtr,
                    bytesPerRow: bytesPerRow,
                    bytesPerImage: 0  // Not used for 2D array
                )
            }
        }

        print("✅ Created 2D array texture: \(Self.volumeSize)×\(Self.volumeSize)×\(Self.volumeSize)")
        return texture
    }

    // MARK: - Utilities

    private func computeChecksum(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0
        let sampleSize = min(1024, data.count)

        data.prefix(sampleSize).forEach { byte in
            checksum = checksum &+ UInt32(byte)
        }

        return checksum
    }

    // MARK: - Validation

    public func validateVolume(_ volume: Volume3D) {
        let expectedSize = UInt32(Self.volumeSize)
        let isValid = volume.size.x == expectedSize &&
                      volume.size.y == expectedSize &&
                      volume.size.z == expectedSize

        print("🔍 Volume Validation:")
        print("   Size valid: \(isValid ? "✅" : "❌")")
        print("   Non-zero checksum: \(volume.checksum != 0 ? "✅" : "❌")")
        print("   Frame count: \(volume.frameDurations.count)")
        print("   Total duration: \(volume.totalDuration)s")

        if !isValid {
            print("   ⚠️ Volume size mismatch! Expected \(expectedSize)³, got \(volume.size)")
        }
    }
}

// MARK: - Demo Data Generator

extension GifVolumeLoader {

    /// Generate a demo 128³ RGBA volume with gradient
    public static func generateDemoVolume(device: MTLDevice) -> Volume3D? {
        var data = Data(capacity: totalBytes)

        // Generate RGB gradient volume
        for z in 0..<volumeSize {
            for y in 0..<volumeSize {
                for x in 0..<volumeSize {
                    let r = UInt8((x * 255) / (volumeSize - 1))
                    let g = UInt8((y * 255) / (volumeSize - 1))
                    let b = UInt8((z * 255) / (volumeSize - 1))
                    let a: UInt8 = 200  // Non-zero alpha

                    data.append(contentsOf: [r, g, b, a])
                }
            }
        }

        let loader = GifVolumeLoader(device: device)
        guard let texture = loader.createMetal3DTexture(from: data) else {
            return nil
        }

        return Volume3D(
            texture: texture,
            size: SIMD3<UInt32>(UInt32(volumeSize), UInt32(volumeSize), UInt32(volumeSize)),
            frameDurations: Array(repeating: 0.1, count: volumeSize),
            totalDuration: Float(volumeSize) * 0.1,
            checksum: loader.computeChecksum(data)
        )
    }
}
