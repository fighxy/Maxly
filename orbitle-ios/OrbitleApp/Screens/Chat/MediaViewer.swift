import AVKit
import SwiftUI
import UIKit
import OrbitlePresentation

struct MediaViewer: View {
    let request: MediaViewerRequest
    let onClose: () -> Void
    @State private var selection: String
    @State private var zoomed = false

    init(request: MediaViewerRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
        _selection = State(initialValue: request.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(request.slides) { slide in
                    page(slide)
                        .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            if request.slides.count > 1, let label = pageLabel {
                Text(label)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Закрыть")
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let down = value.translation.height
                guard !zoomed, down > 120, down > abs(value.translation.width) else { return }
                onClose()
            }
        )
        .onChange(of: selection) { _, _ in zoomed = false }
    }

    private var pageLabel: String? {
        guard let index = request.slides.firstIndex(where: { $0.id == selection }) else { return nil }
        return "\(index + 1) / \(request.slides.count)"
    }

    @ViewBuilder
    private func page(_ slide: MediaSlide) -> some View {
        if slide.isVideo, let url = slide.playURL {
            PlayerPage(url: url)
        } else {
            ZoomableImage(url: slide.stillURL) { zoomed = $0 }
        }
    }
}

/// Плеер не меняет адрес после старта: подмена файла из кэша не должна перезапускать ролик.
private struct PlayerPage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}

/// Фото с жестом увеличения. Пока масштаб больше единицы, экран не закрывается смахиванием.
private struct ZoomableImage: UIViewRepresentable {
    let url: URL?
    let onZoom: (Bool) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .black
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        scroll.addSubview(imageView)
        context.coordinator.scroll = scroll
        context.coordinator.imageView = imageView
        context.coordinator.load(url)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.layout()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoom: onZoom)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let onZoom: (Bool) -> Void
        weak var scroll: UIScrollView?
        var imageView: UIImageView?
        private var task: URLSessionDataTask?

        init(onZoom: @escaping (Bool) -> Void) {
            self.onZoom = onZoom
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center()
            onZoom(scrollView.zoomScale > 1.01)
        }

        func load(_ url: URL?) {
            task?.cancel()
            imageView?.image = nil
            guard let url else { return }
            if url.isFileURL {
                imageView?.image = UIImage(contentsOfFile: url.path)
                layout()
                return
            }
            task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.imageView?.image = image
                    self.layout()
                }
            }
            task?.resume()
        }

        func layout() {
            guard let scroll, scroll.zoomScale <= 1.01, let imageView, let image = imageView.image else { return }
            let bounds = scroll.bounds
            guard bounds.width > 1, bounds.height > 1, image.size.width > 0, image.size.height > 0 else { return }
            let fitted = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * fitted, height: image.size.height * fitted)
            if scroll.zoomScale == 1 {
                imageView.frame = CGRect(origin: .zero, size: size)
                scroll.contentSize = size
            }
            center()
        }

        private func center() {
            guard let scroll, let imageView else { return }
            let bounds = scroll.bounds
            var frame = imageView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
            imageView.frame = frame
        }
    }
}
