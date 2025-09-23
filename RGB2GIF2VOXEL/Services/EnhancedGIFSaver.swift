//
//  EnhancedGIFSaver.swift
//  RGB2GIF2VOXEL
//
//  Reliable GIF saving to Photos library with proper metadata
//

import Foundation
import Photos
import UniformTypeIdentifiers
import UIKit
import SwiftUI
import Combine
import os.log

private let logger = OSLog(subsystem: "com.yingif.rgb2gif2voxel", category: "GIFSaver")

@MainActor
public class EnhancedGIFSaver: ObservableObject {

    // MARK: - Published Properties

    @Published public var isSaving = false
    @Published public var lastSavedAssetIdentifier: String?
    @Published public var saveError: String?
    @Published public var saveProgress: Double = 0.0

    // MARK: - Permissions Manager

    private let permissionsManager = EnhancedPermissionsManager()

    // MARK: - Save GIF to Photos

    public func saveGIF(_ gifData: Data, filename: String = "voxel") async -> Bool {
        print("💾 Saving GIF to Photos library...")
        print("   Size: \(gifData.count) bytes")
        print("   Filename: \(filename).gif")

        // Check permissions first
        guard await permissionsManager.requestPhotosPermission() else {
            saveError = "Photos permission denied"
            return false
        }

        isSaving = true
        saveProgress = 0.0
        saveError = nil

        do {
            // Create temporary file
            let tempURL = try createTemporaryFile(gifData: gifData, filename: filename)
            saveProgress = 0.3

            // Save to Photos
            let assetIdentifier = try await saveToPhotosLibrary(tempURL: tempURL)
            saveProgress = 0.9

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            // Success!
            lastSavedAssetIdentifier = assetIdentifier
            saveProgress = 1.0
            isSaving = false

            print("✅ GIF saved successfully!")
            print("   Asset ID: \(assetIdentifier)")

            // Verify the save
            await verifyAssetSaved(identifier: assetIdentifier)

            return true

        } catch {
            os_log(.error, log: logger, "Failed to save GIF: %@", error.localizedDescription)
            saveError = error.localizedDescription
            isSaving = false
            return false
        }
    }

    // MARK: - Create Temporary File

    private func createTemporaryFile(gifData: Data, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("\(filename)_\(Date().timeIntervalSince1970).gif")

        try gifData.write(to: tempURL)

        print("   Created temp file: \(tempURL.lastPathComponent)")
        return tempURL
    }

    // MARK: - Save to Photos Library

    private func saveToPhotosLibrary(tempURL: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var assetIdentifier: String?

            PHPhotoLibrary.shared().performChanges({
                // Create asset creation request
                let creationRequest = PHAssetCreationRequest.forAsset()

                // Add the GIF file
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = tempURL.lastPathComponent
                options.uniformTypeIdentifier = UTType.gif.identifier

                creationRequest.addResource(
                    with: .photo,
                    fileURL: tempURL,
                    options: options
                )

                // Store the identifier
                assetIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier

                print("   Creating asset with ID: \(assetIdentifier ?? "unknown")")

            }, completionHandler: { success, error in
                if success, let identifier = assetIdentifier {
                    continuation.resume(returning: identifier)
                } else {
                    continuation.resume(throwing: error ?? SaveError.unknown)
                }
            })
        }
    }

    // MARK: - Save GIF Data Directly

    public func saveGIFData(_ gifData: Data, filename: String = "rgb2gif2voxel") async -> Bool {
        print("💾 Direct GIF data save...")

        // Check permissions
        guard await permissionsManager.requestPhotosPermission() else {
            saveError = "Photos permission denied"
            return false
        }

        isSaving = true
        saveProgress = 0.0
        saveError = nil

        do {
            var savedIdentifier: String?

            try await PHPhotoLibrary.shared().performChanges {
                // Create asset directly from data
                let creationRequest = PHAssetCreationRequest.forAsset()

                // Create resource options
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "\(filename).gif"
                options.uniformTypeIdentifier = UTType.gif.identifier

                // Add GIF data as resource
                creationRequest.addResource(
                    with: .photo,
                    data: gifData,
                    options: options
                )

                // Metadata
                if let creationDate = Date() as NSDate? {
                    creationRequest.creationDate = creationDate as Date
                }

                savedIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
            }

            if let identifier = savedIdentifier {
                lastSavedAssetIdentifier = identifier
                saveProgress = 1.0
                isSaving = false

                // Phase 6: Enhanced logging for verification
                print("✅ GIF saved directly from data!")
                print("   Asset ID: \(identifier)")
                print("   Filename: \(filename).gif")
                print("   UTI: \(UTType.gif.identifier)")
                print("   Size: \(gifData.count) bytes")

                await verifyAssetSaved(identifier: identifier)
                return true
            } else {
                throw SaveError.noIdentifier
            }

        } catch {
            os_log(.error, log: logger, "Direct save failed: %@", error.localizedDescription)
            saveError = error.localizedDescription
            isSaving = false
            return false
        }
    }

    // MARK: - Verify Asset Saved

    private func verifyAssetSaved(identifier: String) async {
        print("🔍 Verifying saved asset...")

        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        )

        guard let asset = fetchResult.firstObject else {
            print("   ❌ Asset not found!")
            return
        }

        print("   ✅ Asset verified!")
        print("   Created: \(asset.creationDate ?? Date())")
        print("   Type: \(asset.mediaType == .image ? "Image" : "Other")")
        print("   Duration: \(asset.duration)s")

        // Check which album it's in
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(
            asset,
            with: .album,
            options: nil
        )

        albums.enumerateObjects { collection, _, _ in
            print("   Album: \(collection.localizedTitle ?? "Unknown")")
        }
    }

    // MARK: - Open in Photos

    public func openInPhotos() {
        guard let identifier = lastSavedAssetIdentifier else {
            print("No saved asset to open")
            return
        }

        // Create Photos URL
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Share GIF

    public func shareGIF(_ gifData: Data) {
        let activityVC = UIActivityViewController(
            activityItems: [gifData],
            applicationActivities: nil
        )

        // Metadata for sharing
        activityVC.setValue("Check out my RGB2GIF2VOXEL creation!", forKey: "subject")

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Error Types

    enum SaveError: LocalizedError {
        case unknown
        case noIdentifier
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .unknown:
                return "An unknown error occurred while saving"
            case .noIdentifier:
                return "Failed to get asset identifier"
            case .permissionDenied:
                return "Permission to save photos was denied"
            }
        }
    }
}

// MARK: - Save Status View

public struct GIFSaveStatusView: View {
    @ObservedObject var saver: EnhancedGIFSaver

    public var body: some View {
        if saver.isSaving {
            VStack(spacing: 20) {
                ProgressView(value: saver.saveProgress)
                    .progressViewStyle(.linear)

                Text("Saving GIF to Photos...")
                    .font(.headline)

                Text("\(Int(saver.saveProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let error = saver.saveError {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)

                Text("Save Failed")
                    .font(.headline)

                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if saver.lastSavedAssetIdentifier != nil {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green)

                Text("Saved to Photos!")
                    .font(.headline)

                Button("Open in Photos") {
                    saver.openInPhotos()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}