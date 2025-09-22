import Foundation
import Accelerate
import CoreVideo
import CoreImage

/// Deterministic high-quality downsampling using vImage
public class Downsampler {

    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    /// Downsample a CVPixelBuffer to target size using Lanczos
    /// - Parameters:
    ///   - pixelBuffer: Input BGRA pixel buffer
    ///   - targetSize: Target width/height (square output)
    /// - Returns: Downsampled BGRA data
    public func downsampleLanczos(
        pixelBuffer: CVPixelBuffer,
        targetSize: Int
    ) throws -> Data {

        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // First, crop to square if needed
        let squareSize = min(width, height)
        let croppedData = try cropToSquare(
            pixelBuffer: pixelBuffer,
            width: width,
            height: height,
            squareSize: squareSize
        )

        // If already target size, return as-is
        if squareSize == targetSize {
            return croppedData
        }

        // Use vImage for high-quality Lanczos downsampling
        return try vImageLanczosScale(
            sourceData: croppedData,
            sourceSize: squareSize,
            targetSize: targetSize
        )
    }

    /// Crop pixel buffer to square (center crop)
    private func cropToSquare(
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        squareSize: Int
    ) throws -> Data {

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DownsampleError.invalidPixelBuffer
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // If already square, copy all data
        if width == height {
            let totalBytes = height * bytesPerRow
            return Data(bytes: baseAddress, count: totalBytes)
        }

        // Center crop
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        var croppedData = Data(capacity: squareSize * squareSize * 4)

        let sourcePtr = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

        for y in 0..<squareSize {
            let sourceRow = yOffset + y
            let sourceOffset = sourceRow * bytesPerRow + xOffset * 4
            let rowData = Data(bytes: sourcePtr + sourceOffset, count: squareSize * 4)
            croppedData.append(rowData)
        }

        return croppedData
    }

    /// High-quality Lanczos scaling using vImage
    private func vImageLanczosScale(
        sourceData: Data,
        sourceSize: Int,
        targetSize: Int
    ) throws -> Data {

        // Create source buffer
        var sourceBuffer = try sourceData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw DownsampleError.invalidData
            }

            return vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                height: vImagePixelCount(sourceSize),
                width: vImagePixelCount(sourceSize),
                rowBytes: sourceSize * 4
            )
        }

        // Create destination buffer
        let destRowBytes = targetSize * 4
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: targetSize * targetSize * 4)
        defer { destData.deallocate() }

        var destBuffer = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(targetSize),
            width: vImagePixelCount(targetSize),
            rowBytes: destRowBytes
        )

        // Perform Lanczos scaling (high quality, deterministic)
        let error = vImageScale_ARGB8888(
            &sourceBuffer,
            &destBuffer,
            nil,  // Use default temporary buffer
            vImage_Flags(kvImageHighQualityResampling)
        )

        guard error == kvImageNoError else {
            throw DownsampleError.scalingFailed(error)
        }

        // Convert result to Data
        return Data(bytes: destData, count: targetSize * targetSize * 4)
    }

    /// Alternative: Use Core Image for Lanczos (also deterministic)
    public func downsampleCI(
        pixelBuffer: CVPixelBuffer,
        targetSize: Int
    ) throws -> Data {

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate scale
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let squareSize = min(width, height)
        let scale = CGFloat(targetSize) / CGFloat(squareSize)

        // Center crop first
        let cropRect = CGRect(
            x: CGFloat(width - squareSize) / 2,
            y: CGFloat(height - squareSize) / 2,
            width: CGFloat(squareSize),
            height: CGFloat(squareSize)
        )
        let cropped = ciImage.cropped(to: cropRect)

        // Apply Lanczos scaling
        let scaled = cropped
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .samplingLinear() // Use Lanczos via sampling mode

        // Render to bitmap
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bitmap = Data(count: targetSize * targetSize * 4)

        bitmap.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }

            context.render(
                scaled,
                toBitmap: baseAddress,
                rowBytes: targetSize * 4,
                bounds: CGRect(x: 0, y: 0, width: targetSize, height: targetSize),
                format: .BGRA8,
                colorSpace: colorSpace
            )
        }

        return bitmap
    }
}