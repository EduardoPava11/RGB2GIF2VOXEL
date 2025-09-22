//
//  PermissionCheckView.swift
//  RGB2GIF2VOXEL
//
//  Camera permission check wrapper
//

import SwiftUI
import AVFoundation

struct PermissionCheckView: View {
    @State private var cameraAuthorized = false
    @State private var checkingPermission = true

    var body: some View {
        if checkingPermission {
            VStack {
                ProgressView()
                    .scaleEffect(2)
                Text("Checking camera permission...")
                    .padding(.top)
            }
            .onAppear {
                checkCameraPermission()
            }
        } else if cameraAuthorized {
            CameraScreen()
        } else {
            CameraPermissionRequestView { granted in
                cameraAuthorized = granted
                checkingPermission = false
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            checkingPermission = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    checkingPermission = false
                }
            }
        case .denied, .restricted:
            cameraAuthorized = false
            checkingPermission = false
        @unknown default:
            cameraAuthorized = false
            checkingPermission = false
        }
    }
}

struct CameraPermissionRequestView: View {
    let onPermissionResult: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Camera Access Required")
                .font(.title)
                .fontWeight(.bold)

            Text("RGB2GIF2VOXEL needs camera access to capture frames for GIF creation")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: requestPermission) {
                Text("Grant Camera Access")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }

            Button(action: openSettings) {
                Text("Open Settings")
                    .foregroundColor(.blue)
            }
        }
        .padding()
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                onPermissionResult(granted)
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    PermissionCheckView()
}