//
//  EnhancedPermissionsManager.swift
//  RGB2GIF2VOXEL
//
//  Graceful permissions handling with beautiful UI
//

import Foundation
import AVFoundation
import Photos
import SwiftUI
import Combine

@MainActor
public class EnhancedPermissionsManager: ObservableObject {

    // MARK: - Published Properties

    @Published public var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published public var photosStatus: PHAuthorizationStatus = .notDetermined
    @Published public var showingCameraExplainer = false
    @Published public var showingPhotosExplainer = false
    @Published public var showingSettingsAlert = false

    // MARK: - Initialization

    public init() {
        updateStatuses()
    }

    // MARK: - Status Updates

    private func updateStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    // MARK: - Camera Permission

    public func requestCameraPermission() async -> Bool {
        print("📷 Requesting camera permission...")

        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            print("   ✅ Camera already authorized")
            return true

        case .notDetermined:
            print("   🤔 Camera permission not determined, requesting...")
            showingCameraExplainer = true

            // Wait a moment for the explainer to show
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                self.cameraStatus = granted ? .authorized : .denied
                self.showingCameraExplainer = false
            }

            print("   Camera permission: \(granted ? "✅ Granted" : "❌ Denied")")
            return granted

        case .restricted, .denied:
            print("   ❌ Camera permission denied/restricted")
            await MainActor.run {
                self.showingSettingsAlert = true
            }
            return false

        @unknown default:
            print("   ⚠️ Unknown camera permission status")
            return false
        }
    }

    // MARK: - Photos Permission

    public func requestPhotosPermission() async -> Bool {
        print("📸 Requesting photos permission...")

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized:
            print("   ✅ Photos already authorized")
            return true

        case .limited:
            print("   ⚠️ Photos limited access - treating as success")
            return true  // Limited is OK for saving

        case .notDetermined:
            print("   🤔 Photos permission not determined, requesting...")
            showingPhotosExplainer = true

            // Wait a moment for the explainer to show
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second

            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            await MainActor.run {
                self.photosStatus = newStatus
                self.showingPhotosExplainer = false
            }

            let success = (newStatus == .authorized || newStatus == .limited)
            print("   Photos permission: \(success ? "✅ Granted" : "❌ Denied")")
            return success

        case .restricted, .denied:
            print("   ❌ Photos permission denied/restricted")
            await MainActor.run {
                self.showingSettingsAlert = true
            }
            return false

        @unknown default:
            print("   ⚠️ Unknown photos permission status")
            return false
        }
    }

    // MARK: - Settings Navigation

    public func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Permission UI Views

public struct CameraPermissionExplainerView: View {
    @ObservedObject var permissionsManager: EnhancedPermissionsManager

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Camera Access")
                .font(.title)
                .fontWeight(.bold)

            Text("RGB2GIF2VOXEL needs camera access to capture frames for your animated GIF and voxel cube.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Text("We'll capture 256 frames to create a perfect loop!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

public struct PhotosPermissionExplainerView: View {
    @ObservedObject var permissionsManager: EnhancedPermissionsManager

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Save to Photos")
                .font(.title)
                .fontWeight(.bold)

            Text("RGB2GIF2VOXEL needs permission to save your created GIFs to your photo library.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Text("Your GIFs will appear in the 'Recents' album.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

public struct PermissionSettingsAlertView: View {
    @ObservedObject var permissionsManager: EnhancedPermissionsManager

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gear.badge.xmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Permission Required")
                .font(.title)
                .fontWeight(.bold)

            Text("Please enable access in Settings to continue.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                Button("Cancel") {
                    permissionsManager.showingSettingsAlert = false
                }
                .buttonStyle(.bordered)

                Button("Open Settings") {
                    permissionsManager.openAppSettings()
                    permissionsManager.showingSettingsAlert = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}