import SwiftUI
import AVFoundation

/// SwiftUI representable for camera preview layer
struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    let videoGravity: AVLayerVideoGravity

    init(session: AVCaptureSession, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        self.session = session
        self.videoGravity = videoGravity
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = session
        view.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // Update if needed
    }

    class CameraPreviewView: UIView {
        var session: AVCaptureSession? {
            didSet {
                guard let session = session else { return }
                previewLayer.session = session
            }
        }

        var videoGravity: AVLayerVideoGravity = .resizeAspect {
            didSet {
                previewLayer.videoGravity = videoGravity
            }
        }

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        private var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}