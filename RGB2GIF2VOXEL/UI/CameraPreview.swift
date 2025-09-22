//
//  CameraPreview.swift
//  RGB2GIF2VOXEL
//
//  Camera preview layer wrapper for SwiftUI
//

import SwiftUI
import AVFoundation

/// SwiftUI wrapper for AVCaptureVideoPreviewLayer
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var videoOrientation: AVCaptureVideoOrientation

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        // Set initial orientation
        if let connection = view.videoPreviewLayer.connection {
            connection.videoOrientation = videoOrientation

            // Mirror for front camera
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = shouldMirror()
            }
        }

        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // CRITICAL: Update frame to match view bounds (fixes black screen)
        uiView.videoPreviewLayer.frame = uiView.bounds

        // Update orientation when it changes
        if let connection = uiView.videoPreviewLayer.connection {
            connection.videoOrientation = videoOrientation

            // Update mirroring
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = shouldMirror()
            }
        }
    }

    private func shouldMirror() -> Bool {
        // Mirror for front camera
        guard let device = session.inputs
            .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
            .first else { return false }
        return device.position == .front
    }

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Ensure preview layer always matches view bounds
            videoPreviewLayer.frame = bounds
        }
    }
}

/// Camera orientation helper
extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight  // Note: inverted
        case .landscapeRight:
            return .landscapeLeft   // Note: inverted
        default:
            return .portrait
        }
    }
}