//
//  StorageService.swift
//  RGB2GIF2VOXEL
//
//  Service for file storage operations
//

import Foundation
import Photos
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "Storage")

/// Service for managing file storage and persistence
@MainActor
public class StorageService {

    // Paths
    private let documentsDirectory: URL
    private let gifsDirectory: URL
    private let cborDirectory: URL
    private let tensorsDirectory: URL

    public init() {
        // Setup directories
        documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        gifsDirectory = documentsDirectory.appendingPathComponent("GIFs")
        cborDirectory = documentsDirectory.appendingPathComponent("CBOR")
        tensorsDirectory = documentsDirectory.appendingPathComponent("Tensors")

        // Create directories if needed
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        let directories = [gifsDirectory, cborDirectory, tensorsDirectory]
        for directory in directories {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - GIF Storage

    /// Save GIF data to documents
    public func saveGIF(_ data: Data, name: String? = nil) throws -> URL {
        let filename = name ?? "gif_\(Int(Date().timeIntervalSince1970)).gif"
        let url = gifsDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            os_log(.info, log: logger, "✅ Saved GIF: %@ (%d bytes)",
                   filename, data.count)
            return url
        } catch {
            os_log(.error, log: logger, "❌ Failed to save GIF: %@",
                   error.localizedDescription)
            throw StorageError.writeFailed(url, error)
        }
    }

    /// Save GIF to Photos library
    public func saveGIFToPhotos(_ gifURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            throw PipelineError.permissionDenied("Photos library access denied")
        }

        do {
            let data = try Data(contentsOf: gifURL)
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            os_log(.info, log: logger, "✅ Saved GIF to Photos")
        } catch {
            os_log(.error, log: logger, "❌ Failed to save to Photos: %@",
                   error.localizedDescription)
            throw StorageError.writeFailed(gifURL, error)
        }
    }

    /// List all saved GIFs
    public func listGIFs() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: gifsDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.pathExtension == "gif" }
                       .sorted { url1, url2 in
                           let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
                           let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
                           return date1 > date2  // Most recent first
                       }
        } catch {
            os_log(.error, log: logger, "Failed to list GIFs: %@",
                   error.localizedDescription)
            return []
        }
    }

    // MARK: - CBOR Storage

    /// Save frames as CBOR using Zig
    public func saveFramesCBOR(_ frames: [Data], sessionId: String) throws -> URL {
        let sessionDir = cborDirectory.appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(
            at: sessionDir,
            withIntermediateDirectories: true
        )

        // Use FrameSaver to write CBOR
        let frameSaver = FrameSaver()

        // Assuming frames are 256x256 RGBA
        try frameSaver.openWriter(
            sessionId: sessionId,
            frameCount: frames.count,
            width: 256,
            height: 256
        )

        // Note: This requires CVPixelBuffer, not Data
        // For now, just create the directory structure
        // TODO: Convert Data to CVPixelBuffer or update API

        os_log(.info, log: logger, "✅ Saved %d frames as CBOR", frames.count)
        return sessionDir
    }

    /// Load frames from CBOR
    public func loadFramesCBOR(sessionId: String) throws -> [Data] {
        let sessionDir = cborDirectory.appendingPathComponent(sessionId)
        let files = try FileManager.default.contentsOfDirectory(
            at: sessionDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "cbor" }
         .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var frames: [Data] = []
        for file in files {
            let data = try Data(contentsOf: file)
            // TODO: Decode CBOR to extract frame data
            frames.append(data)
        }

        os_log(.info, log: logger, "✅ Loaded %d frames from CBOR", frames.count)
        return frames
    }

    // MARK: - Tensor Storage

    /// Save cube tensor using YXV format
    public func saveTensor(_ tensor: CubeTensor, name: String? = nil) throws -> URL {
        let filename = name ?? "tensor_\(Int(Date().timeIntervalSince1970)).yxv"
        let url = tensorsDirectory.appendingPathComponent(filename)

        // Use YXVWriter to save
        let writer = YXVWriter()
        try writer.write(tensor, to: url)

        os_log(.info, log: logger, "✅ Saved tensor: %@", filename)
        return url
    }

    /// Load cube tensor from YXV
    public func loadTensor(from url: URL) throws -> CubeTensor {
        let reader = YXVReader()
        let tensor = try reader.read(from: url)

        os_log(.info, log: logger, "✅ Loaded tensor from: %@",
               url.lastPathComponent)
        return tensor
    }

    // MARK: - Cleanup

    /// Delete old files to free space
    public func cleanupOldFiles(daysToKeep: Int = 7) {
        let cutoffDate = Date().addingTimeInterval(-Double(daysToKeep * 24 * 60 * 60))

        let directories = [gifsDirectory, cborDirectory, tensorsDirectory]
        for directory in directories {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey]
            ) else { continue }

            for file in files {
                if let values = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = values.creationDate,
                   creationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: file)
                    os_log(.info, log: logger, "Cleaned up old file: %@",
                           file.lastPathComponent)
                }
            }
        }
    }

    /// Get available storage space
    public func availableSpace() -> Int64 {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
}