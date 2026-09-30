import AVKit
import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation

struct MediaViewer: View {
    let request: MediaViewerRequest
    /// Скачать ролик целиком, если поток не открылся.
    var download: (MediaSlide) async -> URL? = { $0.playURL }
    let onClose: () -> Void
    @State private var selection: String
    @State private var zoomed = false

    init(request: MediaViewerRequest, download: @escaping (MediaSlide) async -> URL? = { $0.playURL }, onClose: @escaping () -> Void) {
        self.request = request
        self.download = download
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
            VideoPage(url: url, poster: slide.stillURL, active: selection == slide.id) {
                await download(slide)
            }
        } else {
            ZoomableImage(url: slide.stillURL) { zoomed = $0 }
        }
    }
}

/// Страница ролика: системный плеер с управлением, загрузка и ошибка поверх.
///
/// Если поток не открылся (`AVPlayerItem.status == .failed`), ролик один раз скачивается
/// целиком и играет с диска. Если не вышло и так — видна ошибка с кнопкой «Повторить».
/// Уходя со страницы (листание альбома), ролик ставится на паузу.
private struct VideoPage: View {
    let url: URL
    let poster: URL?
    let active: Bool
    let download: () async -> URL?
    @State private var player = VideoPlayback()

    var body: some View {
        ZStack {
            PlayerController(player: player.player)
            switch player.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            case .failed:
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                    Text("Не удалось воспроизвести видео")
                        .font(.headline)
                    Button("Повторить") { player.start(url: url, download: download) }
                        .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            case .ready:
                EmptyView()
            }
        }
        .onAppear { player.start(url: url, download: download) }
        .onChange(of: active) { _, isActive in
            if isActive { player.player.play() } else { player.player.pause() }
        }
        .onDisappear { player.stop() }
    }
}

/// Состояние воспроизведения одного ролика.
@MainActor
@Observable
private final class VideoPlayback {
    enum State { case loading, ready, failed }

    let player = AVPlayer()
    private(set) var state: State = .loading
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var triedDownload = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var fallback: (() async -> URL?)?

    func start(url: URL, download: @escaping () async -> URL?) {
        triedDownload = false
        fallback = download
        play(url)
    }

    func stop() {
        task?.cancel()
        observation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func play(_ url: URL) {
        state = .loading
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let item: AVPlayerItem
        if !url.isFileURL, let agent = MediaHTTP.userAgent {
            item = AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: agent]))
        } else {
            item = AVPlayerItem(url: url)
        }
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error.map { "\($0)" } ?? ""
            Task { @MainActor [weak self] in self?.itemChanged(status, error: message) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func itemChanged(_ status: AVPlayerItem.Status, error: String) {
        switch status {
        case .readyToPlay:
            state = .ready
        case .failed:
            Log.warning(.media, "Видео не открылось потоком: \(error)")
            guard !triedDownload else {
                state = .failed
                return
            }
            triedDownload = true
            guard let fallback else {
                state = .failed
                return
            }
            task = Task { [weak self] in
                guard let file = await fallback(), !Task.isCancelled else {
                    self?.state = .failed
                    return
                }
                self?.play(file)
            }
        default:
            break
        }
    }
}

/// Системный плеер с управлением. Плеер передаётся снаружи, чтобы подмена ролика
/// (скачанный файл вместо потока) не пересоздавала экран.
private struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
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
