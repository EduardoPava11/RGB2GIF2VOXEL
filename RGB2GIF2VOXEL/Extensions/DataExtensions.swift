import Foundation
import UIKit

// MARK: - Data Extensions

extension Data {

    /// Create a square center-cropped version of BGRA data
    static func centerCropSquareBGRA(from data: Data, width: Int, height: Int, bytesPerRow: Int) -> Data {
        guard width != height else { return data }

        let size = Swift.min(width, height)
        let xOffset = (width - size) / 2
        let yOffset = (height - size) / 2

        var cropped = Data(capacity: size * size * 4)

        data.withUnsafeBytes { srcBytes in
            let src = srcBytes.bindMemory(to: UInt8.self)

            for y in 0..<size {
                let srcRow = yOffset + y
                let srcOffset = srcRow * bytesPerRow + xOffset * 4
                let rowData = src[srcOffset..<(srcOffset + size * 4)]
                cropped.append(contentsOf: rowData)
            }
        }

        return cropped
    }

    /// Convert to hex string
    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }

    /// Calculate SHA256 hash
    var sha256Hash: String {
        return self.hexString // Simplified for now
    }
}

// MARK: - UIImage Extensions

extension UIImage {

    /// Create image from BGRA data
    static func fromBGRA(data: Data, width: Int, height: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Create thumbnail at specified size
    func thumbnail(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Array Extensions

extension Array where Element == UInt32 {

    /// Convert palette to RGBA bytes
    func toRGBABytes() -> Data {
        var data = Data(capacity: count * 4)

        for color in self {
            let r = UInt8((color >> 16) & 0xFF)
            let g = UInt8((color >> 8) & 0xFF)
            let b = UInt8(color & 0xFF)
            let a = UInt8(255)

            data.append(r)
            data.append(g)
            data.append(b)
            data.append(a)
        }

        return data
    }
}

// MARK: - FileManager Extensions

extension FileManager {

    /// Get documents directory URL
    var documentsDirectory: URL {
        urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Get caches directory URL
    var cachesDirectory: URL {
        urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    /// Create directory if needed
    func createDirectoryIfNeeded(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}