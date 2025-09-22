//
//  CaptureCoordinator.swift
//  RGB2GIF2VOXEL
//
//  Coordinator for capture pipeline operations
//

import Foundation

/// Coordinates capture pipeline operations
@MainActor
public class CaptureCoordinator {

    public init() {}

    /// Export tensor to YXV format
    public func exportYXV(tensor: CubeTensorData) async -> URL? {
        do {
            // Convert CubeTensorData to CubeTensor
            let frames = createQuantizedFrames(from: tensor)
            let cubeTensor = CubeTensor(
                frames: frames,
                sideN: tensor.size,
                paletteSize: tensor.paletteSize
            )

            // Save using YXVWriter
            let writer = YXVWriter()
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let yxvPath = documentsPath.appendingPathComponent("exports")
            try FileManager.default.createDirectory(at: yxvPath, withIntermediateDirectories: true)

            let url = yxvPath.appendingPathComponent("tensor_\(Date().timeIntervalSince1970).yxv")
            try writer.write(cubeTensor, to: url)

            return url
        } catch {
            print("Failed to export YXV: \(error)")
            return nil
        }
    }

    /// Convert CubeTensorData to QuantizedFrames
    private func createQuantizedFrames(from tensorData: CubeTensorData) -> [QuantizedFrame] {
        var frames: [QuantizedFrame] = []
        let frameSize = tensorData.size * tensorData.size

        for frameIdx in 0..<tensorData.size {
            let startIdx = frameIdx * frameSize
            let endIdx = min(startIdx + frameSize, tensorData.indices.count)
            let frameIndices = Data(tensorData.indices[startIdx..<endIdx])

            // Convert indices and palette to RGBA data for new API
            var rgbaData = Data(capacity: frameSize * 4)
            for byte in frameIndices {
                let colorIndex = Int(byte) % tensorData.palette.count
                let color = tensorData.palette[colorIndex]
                rgbaData.append(UInt8((color >> 16) & 0xFF)) // R
                rgbaData.append(UInt8((color >> 8) & 0xFF))  // G
                rgbaData.append(UInt8(color & 0xFF))         // B
                rgbaData.append(0xFF)                        // A
            }

            let frame = QuantizedFrame(
                index: frameIdx,
                data: rgbaData,
                width: tensorData.size,
                height: tensorData.size
            )
            frames.append(frame)
        }

        return frames
    }
}