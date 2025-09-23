//
//  CameraPreviewView.swift
//  RGB2GIF2VOXEL
//
//  Proper AVCaptureVideoPreviewLayer implementation
//

import UIKit
import AVFoundation
import SwiftUI
import os

// MARK: - UIKit Preview View

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    func attach(_ session: AVCaptureSession) {
        Log.camera.info("Attaching camera session to preview layer")
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Critical: update frame on layout changes
        previewLayer.frame = bounds
        Log.camera.debug("Preview layer frame updated: \(self.bounds.debugDescription)")
    }
}

// MARK: - SwiftUI Wrapper

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.attach(session)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Ensure session is attached on updates
        if uiView.previewLayer.session != session {
            uiView.attach(session)
        }
    }

    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.previewLayer.session = nil
    }
}

// MARK: - Square Preview Wrapper
// Note: SquareCameraPreview is defined in SimplifiedCameraView.swift