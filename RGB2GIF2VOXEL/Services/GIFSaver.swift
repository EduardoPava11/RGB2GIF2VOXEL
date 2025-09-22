import Foundation
import Combine
import Photos
import UIKit

/// Manages saving GIF files to the iOS Photos library
@MainActor
public class GIFSaver: ObservableObject {

    // MARK: - Published Properties
    @Published public private(set) var isSaving = false
    @Published public private(set) var lastSaveResult: SaveResult?
    @Published public private(set) var saveProgress: Double = 0.0

    // MARK: - Save Result
    public struct SaveResult {
        public let success: Bool
        public let localIdentifier: String?
        public let error: Error?
        public let timestamp: Date

        public var message: String {
            if success {
                return "GIF saved successfully!"
            } else {
                return error?.localizedDescription ?? "Failed to save GIF"
            }
        }
    }

    // MARK: - Errors
    public enum SaveError: LocalizedError {
        case noPermission
        case invalidData
        case saveFailed(String)
        case assetCreationFailed

        public var errorDescription: String? {
            switch self {
            case .noPermission:
                return "Photo library permission denied"
            case .invalidData:
                return "Invalid GIF data"
            case .saveFailed(let reason):
                return "Save failed: \(reason)"
            case .assetCreationFailed:
                return "Failed to create photo asset"
            }
        }
    }

    // MARK: - Main Save Function

    /// Save GIF data to Photos library
    /// - Parameter gifData: The GIF file data to save
    /// - Returns: SaveResult indicating success or failure
    @discardableResult
    public func saveGIF(_ gifData: Data) async -> SaveResult {
        await MainActor.run {
            self.isSaving = true
            self.saveProgress = 0.0
        }

        // Check permissions first
        let permissionStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard permissionStatus == .authorized || permissionStatus == .limited else {
            let error = SaveError.noPermission
            let result = SaveResult(success: false, localIdentifier: nil, error: error, timestamp: Date())
            await MainActor.run {
                self.lastSaveResult = result
                self.isSaving = false
            }
            return result
        }

        // Validate GIF data
        guard gifData.count > 0, isValidGIF(gifData) else {
            let error = SaveError.invalidData
            let result = SaveResult(success: false, localIdentifier: nil, error: error, timestamp: Date())
            await MainActor.run {
                self.lastSaveResult = result
                self.isSaving = false
            }
            return result
        }

        // Save to temporary file first
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")

        do {
            try gifData.write(to: tempURL)
            await MainActor.run {
                self.saveProgress = 0.3
            }
        } catch {
            let saveError = SaveError.saveFailed(error.localizedDescription)
            let result = SaveResult(success: false, localIdentifier: nil, error: saveError, timestamp: Date())
            await MainActor.run {
                self.lastSaveResult = result
                self.isSaving = false
            }
            return result
        }

        // Save to Photos library
        var localIdentifier: String?
        var saveError: Error?

        do {
            try await PHPhotoLibrary.shared().performChanges {
                // Create asset from GIF file
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: tempURL, options: nil)
                localIdentifier = request.placeholderForCreatedAsset?.localIdentifier

                // Add creation metadata
                let creationDate = Date()
                request.creationDate = creationDate

                // Add to a custom album if desired
                if let album = self.getOrCreateAlbum(named: "RGB2GIF2VOXEL") {
                    if let placeholder = request.placeholderForCreatedAsset {
                        let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                        albumChangeRequest?.addAssets([placeholder] as NSArray)
                    }
                }
            }

            await MainActor.run {
                self.saveProgress = 1.0
            }

        } catch {
            saveError = error
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        // Create result
        let result = SaveResult(
            success: saveError == nil,
            localIdentifier: localIdentifier,
            error: saveError,
            timestamp: Date()
        )

        await MainActor.run {
            self.lastSaveResult = result
            self.isSaving = false
        }

        return result
    }

    // MARK: - Album Management

    /// Get or create a custom album for the app
    private func getOrCreateAlbum(named albumName: String) -> PHAssetCollection? {
        // Check if album already exists
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        if let existingAlbum = collections.firstObject {
            return existingAlbum
        }

        // Create new album
        var albumIdentifier: String?
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                albumIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            print("Failed to create album: \(error)")
            return nil
        }

        // Fetch the created album
        if let identifier = albumIdentifier {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
            return collections.firstObject
        }

        return nil
    }

    // MARK: - Validation

    /// Check if data represents a valid GIF
    private func isValidGIF(_ data: Data) -> Bool {
        // Check for GIF header
        guard data.count > 6 else { return false }
        let header = data.prefix(6)
        return header == Data("GIF87a".utf8) || header == Data("GIF89a".utf8)
    }

    // MARK: - Quick Save

    /// Quick save with automatic permission handling
    public func quickSaveGIF(_ gifData: Data) async -> Bool {
        // Request permission if needed
        let permissionStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if permissionStatus == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                return false
            }
        }

        let result = await saveGIF(gifData)
        return result.success
    }

    // MARK: - Share Sheet

    /// Present share sheet for GIF
    @MainActor
    public func shareGIF(_ gifData: Data, from viewController: UIViewController? = nil) {
        // Save to temp file for sharing
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share_\(UUID().uuidString)")
            .appendingPathExtension("gif")

        do {
            try gifData.write(to: tempURL)
        } catch {
            print("Failed to create temp file for sharing: \(error)")
            return
        }

        // Create activity items
        let activityItems: [Any] = [tempURL]

        // Create activity view controller
        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        // Exclude certain activities if desired
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]

        // Present from the appropriate view controller
        if let presenter = viewController ?? UIApplication.shared.keyWindow?.rootViewController {
            // iPad requires popover
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = presenter.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0,
                    height: 0
                )
            }
            presenter.present(activityVC, animated: true)
        }

        // Clean up temp file after sharing
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: - Retrieve Saved GIF

    /// Fetch a saved GIF by its local identifier
    public func fetchSavedGIF(identifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return fetchResult.firstObject
    }

    /// Load GIF data from PHAsset
    public func loadGIFData(from asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .original
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// SwiftUI view modifier for saving GIFs
struct GIFSaveModifier: ViewModifier {
    @StateObject private var saver = GIFSaver()
    let gifData: Data?
    @State private var showingSaveAlert = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveGIF) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(gifData == nil || saver.isSaving)
                }
            }
            .alert("Save Result", isPresented: $showingSaveAlert) {
                Button("OK") { }
            } message: {
                Text(saver.lastSaveResult?.message ?? "")
            }
    }

    private func saveGIF() {
        guard let data = gifData else { return }
        Task {
            await saver.saveGIF(data)
            showingSaveAlert = true
        }
    }
}

extension View {
    /// Add GIF save functionality to a view
    public func gifSaver(data: Data?) -> some View {
        modifier(GIFSaveModifier(gifData: data))
    }
}