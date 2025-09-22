//
//  PhotosGIFSaver.swift
//  RGB2GIF2VOXEL
//
//  Robust GIF saving to Photos library with proper metadata
//

import Foundation
import Photos
import UniformTypeIdentifiers
import os

public final class PhotosGIFSaver {

    // MARK: - Error Types

    enum SaveError: LocalizedError {
        case permissionDenied
        case saveFailed(String)
        case assetNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photos library permission denied"
            case .saveFailed(let reason):
                return "Failed to save GIF: \(reason)"
            case .assetNotFound:
                return "Saved asset not found in library"
            }
        }
    }

    // MARK: - Public Methods

    public static func saveGIF(
        _ data: Data,
        filename: String = "RGB2GIF_\(Date().timeIntervalSince1970).gif"
    ) async throws -> PHAsset {

        let signpostState = PipelineSignpost.begin(.savePhotos)
        defer { PipelineSignpost.end(.savePhotos, signpostState) }

        // Check permission
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            Log.photos.error("Permission denied: \(String(describing: status))")
            throw SaveError.permissionDenied
        }

        // Create resource options with proper metadata
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = filename
        options.uniformTypeIdentifier = UTType.gif.identifier

        return try await withCheckedThrowingContinuation { continuation in
            var placeholderID: String?

            PHPhotoLibrary.shared().performChanges({
                // Create asset request
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: options)
                placeholderID = creationRequest.placeholderForCreatedAsset?.localIdentifier

                Log.photos.info("Creating GIF asset: \(filename, privacy: .public)")

            }, completionHandler: { success, error in
                if let error = error {
                    Log.photos.error("Save failed: \(error.localizedDescription)")
                    continuation.resume(throwing: SaveError.saveFailed(error.localizedDescription))
                    return
                }

                guard success, let assetID = placeholderID else {
                    Log.photos.error("Save failed: No placeholder ID")
                    continuation.resume(throwing: SaveError.saveFailed("No asset ID returned"))
                    return
                }

                // Verify asset exists by fetching it
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)

                if let asset = fetchResult.firstObject {
                    Log.photos.info("✅ GIF saved successfully: \(assetID, privacy: .public)")

                    // Log additional info about the asset
                    Log.photos.debug("""
                        Asset details:
                        - Type: \(asset.mediaType.rawValue)
                        - Creation date: \(asset.creationDate?.description ?? "unknown")
                        - Duration: \(asset.duration)
                        - Pixel dimensions: \(asset.pixelWidth)x\(asset.pixelHeight)
                        """)

                    continuation.resume(returning: asset)
                } else {
                    Log.photos.error("Asset not found after save: \(assetID)")
                    continuation.resume(throwing: SaveError.assetNotFound)
                }
            })
        }
    }

    // MARK: - Alternative Save Method (with completion handler)

    public static func saveGIF(
        _ data: Data,
        filename: String = "RGB2GIF_\(Date().timeIntervalSince1970).gif",
        completion: @escaping (Result<PHAsset, Error>) -> Void
    ) {
        Task {
            do {
                let asset = try await saveGIF(data, filename: filename)
                completion(.success(asset))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Permission Check

    public static func checkPhotosPermission() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}