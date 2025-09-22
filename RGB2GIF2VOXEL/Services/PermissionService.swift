//
//  PermissionService.swift
//  RGB2GIF2VOXEL
//
//  Centralized permission management with status tracking
//

import Foundation
import AVFoundation
import Photos
import Combine
import UIKit

@MainActor
public class PermissionService: ObservableObject {

    // MARK: - Published State

    @Published public var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published public var photosStatus: PHAuthorizationStatus = .notDetermined
    @Published public var isRequestingPermission = false
    @Published public var lastError: String?

    // MARK: - Initialization

    public init() {
        updateStatuses()
    }

    // MARK: - Status Updates

    /// Update current permission statuses
    public func updateStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        photosStatus = PHPhotoLibrary.authorizationStatus()

        print("📱 [PERMISSIONS] Camera: \(statusString(cameraStatus)), Photos: \(statusString(photosStatus))")
    }

    // MARK: - Camera Permission

    /// Request camera permission if needed
    public func requestCameraPermission() async -> Bool {
        updateStatuses()

        switch cameraStatus {
        case .authorized:
            print("✅ [PERMISSIONS] Camera already authorized")
            return true

        case .notDetermined:
            print("❓ [PERMISSIONS] Requesting camera permission...")
            isRequestingPermission = true

            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    Task { @MainActor in
                        self.isRequestingPermission = false
                        self.cameraStatus = granted ? .authorized : .denied
                        print(granted ? "✅ [PERMISSIONS] Camera granted" : "❌ [PERMISSIONS] Camera denied")
                        continuation.resume(returning: granted)
                    }
                }
            }
            return granted

        case .denied, .restricted:
            print("🚫 [PERMISSIONS] Camera denied/restricted")
            lastError = "Camera access denied. Please enable in Settings."
            return false

        @unknown default:
            print("⚠️ [PERMISSIONS] Unknown camera status")
            return false
        }
    }

    // MARK: - Photos Permission

    /// Request photos permission if needed
    public func requestPhotosPermission() async -> Bool {
        updateStatuses()

        switch photosStatus {
        case .authorized, .limited:
            print("✅ [PERMISSIONS] Photos already authorized")
            return true

        case .notDetermined:
            print("❓ [PERMISSIONS] Requesting photos permission...")
            isRequestingPermission = true

            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { status in
                    Task { @MainActor in
                        self.isRequestingPermission = false
                        self.photosStatus = status
                        let granted = (status == .authorized || status == .limited)
                        print(granted ? "✅ [PERMISSIONS] Photos granted" : "❌ [PERMISSIONS] Photos denied")
                        continuation.resume(returning: granted)
                    }
                }
            }

        case .denied, .restricted:
            print("🚫 [PERMISSIONS] Photos denied/restricted")
            lastError = "Photos access denied. Please enable in Settings."
            return false

        @unknown default:
            print("⚠️ [PERMISSIONS] Unknown photos status")
            return false
        }
    }

    // MARK: - Combined Permission Request

    /// Request all necessary permissions
    public func requestAllPermissions() async -> Bool {
        let cameraGranted = await requestCameraPermission()
        let photosGranted = await requestPhotosPermission()

        if !cameraGranted {
            lastError = "Camera permission is required to capture frames"
        } else if !photosGranted {
            lastError = "Photos permission is optional but recommended for saving GIFs"
        }

        return cameraGranted // Camera is mandatory, photos is optional
    }

    // MARK: - Helpers

    private func statusString(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private func statusString(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .limited: return "limited"
        @unknown default: return "unknown"
        }
    }

    /// Open app settings for user to grant permissions
    public func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}