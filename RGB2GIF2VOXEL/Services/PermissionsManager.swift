import Foundation
import Combine
import AVFoundation
import Photos
import UIKit

/// Manages iOS permissions for camera and photo library access
@MainActor
public class PermissionsManager: ObservableObject {

    // MARK: - Published Properties
    @Published public private(set) var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published public private(set) var photoLibraryPermissionStatus: PHAuthorizationStatus = .notDetermined
    @Published public private(set) var hasCameraAccess = false
    @Published public private(set) var hasPhotoLibraryAccess = false

    // MARK: - Initialization
    public init() {
        checkCurrentPermissions()
    }

    // MARK: - Permission Checking

    /// Check current permission status
    public func checkCurrentPermissions() {
        checkCameraPermission()
        checkPhotoLibraryPermission()
    }

    private func checkCameraPermission() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        hasCameraAccess = cameraPermissionStatus == .authorized
    }

    private func checkPhotoLibraryPermission() {
        photoLibraryPermissionStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        hasPhotoLibraryAccess = photoLibraryPermissionStatus == .authorized
    }

    // MARK: - Permission Requests

    /// Request camera permission
    /// - Returns: true if permission granted, false otherwise
    @discardableResult
    public func requestCameraPermission() async -> Bool {
        // Check current status
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch currentStatus {
        case .authorized:
            await MainActor.run {
                self.hasCameraAccess = true
                self.cameraPermissionStatus = .authorized
            }
            return true

        case .notDetermined:
            // Request permission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                self.hasCameraAccess = granted
                self.cameraPermissionStatus = granted ? .authorized : .denied
            }
            return granted

        case .denied, .restricted:
            await MainActor.run {
                self.hasCameraAccess = false
                self.cameraPermissionStatus = currentStatus
            }
            // Optionally show settings alert
            await showSettingsAlert(for: .camera)
            return false

        @unknown default:
            return false
        }
    }

    /// Request photo library write permission (for saving GIFs)
    /// - Returns: true if permission granted, false otherwise
    @discardableResult
    public func requestPhotoLibraryPermission() async -> Bool {
        // Check current status
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch currentStatus {
        case .authorized, .limited:
            await MainActor.run {
                self.hasPhotoLibraryAccess = true
                self.photoLibraryPermissionStatus = currentStatus
            }
            return true

        case .notDetermined:
            // Request permission
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            let granted = (status == .authorized || status == .limited)
            await MainActor.run {
                self.hasPhotoLibraryAccess = granted
                self.photoLibraryPermissionStatus = status
            }
            return granted

        case .denied, .restricted:
            await MainActor.run {
                self.hasPhotoLibraryAccess = false
                self.photoLibraryPermissionStatus = currentStatus
            }
            // Optionally show settings alert
            await showSettingsAlert(for: .photoLibrary)
            return false

        @unknown default:
            return false
        }
    }

    /// Request both camera and photo library permissions
    /// - Returns: tuple indicating (camera granted, photos granted)
    public func requestAllPermissions() async -> (camera: Bool, photos: Bool) {
        async let cameraResult = requestCameraPermission()
        async let photosResult = requestPhotoLibraryPermission()

        return await (cameraResult, photosResult)
    }

    // MARK: - Settings Alert

    public enum PermissionType {
        case camera
        case photoLibrary

        var title: String {
            switch self {
            case .camera:
                return "Camera Access Required"
            case .photoLibrary:
                return "Photo Library Access Required"
            }
        }

        var message: String {
            switch self {
            case .camera:
                return "RGB2GIF2VOXEL needs camera access to capture frames. Please enable camera access in Settings."
            case .photoLibrary:
                return "RGB2GIF2VOXEL needs photo library access to save your GIF creations. Please enable photo library access in Settings."
            }
        }
    }

    /// Show alert directing user to Settings
    @MainActor
    private func showSettingsAlert(for permission: PermissionType) async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(
            title: permission.title,
            message: permission.message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        rootViewController.present(alert, animated: true)
    }

    // MARK: - Permission Status Helpers

    /// Check if all required permissions are granted
    public var hasAllPermissions: Bool {
        hasCameraAccess && hasPhotoLibraryAccess
    }

    /// Get human-readable status message
    public var statusMessage: String {
        if hasAllPermissions {
            return "All permissions granted"
        } else if !hasCameraAccess && !hasPhotoLibraryAccess {
            return "Camera and photo library access needed"
        } else if !hasCameraAccess {
            return "Camera access needed"
        } else {
            return "Photo library access needed"
        }
    }

    /// Permission status for UI display
    public enum PermissionUIStatus {
        case granted
        case partial
        case denied
        case notDetermined
    }

    public var uiStatus: PermissionUIStatus {
        if hasAllPermissions {
            return .granted
        } else if hasCameraAccess || hasPhotoLibraryAccess {
            return .partial
        } else if cameraPermissionStatus == .denied || photoLibraryPermissionStatus == .denied {
            return .denied
        } else {
            return .notDetermined
        }
    }
}

// MARK: - SwiftUI View Modifier

import SwiftUI

/// View modifier to check permissions on appear
struct PermissionCheckModifier: ViewModifier {
    @StateObject private var permissionsManager = PermissionsManager()
    let onComplete: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .task {
                let result = await permissionsManager.requestAllPermissions()
                onComplete(result.camera && result.photos)
            }
            .environmentObject(permissionsManager)
    }
}

extension View {
    /// Check and request permissions when view appears
    public func checkPermissions(onComplete: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(PermissionCheckModifier(onComplete: onComplete))
    }
}