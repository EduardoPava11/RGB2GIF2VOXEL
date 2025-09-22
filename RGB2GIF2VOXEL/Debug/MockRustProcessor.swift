import Foundation
import UIKit

#if DEBUG
/// Mock Rust processor for testing without actual Rust library
public class MockYinGifProcessor {

    public init() {}

    public func processFrame(
        bgraData: Data,
        width: Int,
        height: Int,
        targetSize: Int,
        paletteSize: Int
    ) throws -> QuantizedFrame {
        // Simulate processing delay
        Thread.sleep(forTimeInterval: 0.01)

        // Create mock quantized frame
        let indices = Data(repeating: UInt8.random(in: 0..<UInt8(paletteSize)), count: targetSize * targetSize)
        let palette = (0..<paletteSize).map { i in
            UInt32.random(in: 0x000000...0xFFFFFF)
        }

        // Create mock RGBA data for the frame
        let mockRgbaData = Data(repeating: 0xFF, count: targetSize * targetSize * 4)

        return QuantizedFrame(
            index: 0,  // Mock frame index
            data: mockRgbaData,
            width: targetSize,
            height: targetSize
        )
    }

    public func processFrameAsync(
        bgraData: Data,
        width: Int,
        height: Int,
        targetSize: Int,
        paletteSize: Int
    ) async throws -> QuantizedFrame {
        return try processFrame(
            bgraData: bgraData,
            width: width,
            height: height,
            targetSize: targetSize,
            paletteSize: paletteSize
        )
    }
}

/// Mock GIF encoder for testing
public class MockGIF89aEncoder {

    public static func encode(tensor: CubeTensorData, delayMs: Int = 40) -> Data? {
        // Create mock GIF data
        let header = "GIF89a".data(using: .utf8)!
        let mockData = Data(repeating: 0xFF, count: 1024)
        return header + mockData
    }

    public static func estimateSize(cubeSize: Int, paletteSize: Int) -> Int {
        return cubeSize * cubeSize * cubeSize + 1024
    }
}
#endif