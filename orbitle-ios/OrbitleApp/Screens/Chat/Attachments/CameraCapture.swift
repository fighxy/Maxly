@preconcurrency import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Снимок или видео с камеры системным контроллером.
struct ChatCameraPicker: UIViewControllerRepresentable {
    enum Shot {
        case photo(UIImage)
        case video(URL)
    }

    let onShot: (Shot) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onShot: onShot, onCancel: onCancel) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onShot: (Shot) -> Void
        let onCancel: () -> Void

        init(onShot: @escaping (Shot) -> Void, onCancel: @escaping () -> Void) {
            self.onShot = onShot
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                onShot(.video(url))
            } else if let image = info[.originalImage] as? UIImage {
                onShot(.photo(image))
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

/// Живое превью камеры в первой ячейке галереи. Только если доступ уже дан:
/// сам лист доступ не спрашивает, его спросит системная камера по нажатию.
final class CameraFeed: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "orbitle.attachments.camera")
    private var configured = false

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func start() {
        queue.async { [self] in
            if !configured {
                configured = true
                session.beginConfiguration()
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let feed: CameraFeed

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = feed.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
