import AVFoundation
import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Просмотр историй на весь экран. Касание слева (треть ширины) — назад, справа — вперёд,
/// удержание — пауза, свайп вниз — закрыть, вбок — к соседнему владельцу. Фото идёт 5 секунд,
/// видео — сколько длится.
struct StoryViewerView: View {
    let stories: StoriesViewModel
    @State private var photo: UIImage?
    /// История, чья картинка уже загрузилась: с неё идёт таймер.
    @State private var readyEpoch = -1
    @State private var progress: Double = 0
    @State private var progressEpoch = -1
    @State private var pressing = false
    @State private var pressStart: Date?
    @State private var drag: CGSize = .zero
    @State private var confirmDelete = false
    @State private var video = StoryVideoPlayback()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let viewer = stories.viewer {
                    media(viewer)
                        .offset(y: max(0, drag.height))
                        .scaleEffect(1 - min(max(0, drag.height) / 3000, 0.15))
                        .contentShape(Rectangle())
                        .gesture(touchGesture(width: geometry.size.width))
                    chrome(viewer)
                }
            }
        }
        .statusBarHidden()
        .confirmationDialog("Удалить историю?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await stories.deleteCurrent() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История исчезнет у всех, кто её ещё не посмотрел.")
        }
        .task(id: TimerKey(epoch: stories.viewer?.epoch ?? -1, ready: readyEpoch, holding: holding, asPhoto: asPhoto)) {
            await runTimer()
        }
        .onChange(of: stories.viewer?.epoch) { _, _ in startStory() }
        .onChange(of: holding) { _, held in video.setPaused(held) }
        .onAppear { startStory() }
        .onDisappear { video.stop() }
    }

    // MARK: Содержимое

    private var holding: Bool {
        pressing || confirmDelete || stories.viewer?.isDeleting == true || drag != .zero
    }

    /// Фото, а также видео, которое не открылось: идёт таймер, а не плеер.
    private var asPhoto: Bool {
        guard let media = stories.viewer?.story?.media else { return false }
        return !media.isVideo || video.failed
    }

    @ViewBuilder
    private func media(_ viewer: StoryViewerState) -> some View {
        if viewer.isLoading || viewer.story?.media == nil {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let media = viewer.story?.media {
            ZStack {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                } else if !media.isVideo {
                    ProgressView().tint(.white)
                }
                if media.isVideo && !video.failed {
                    StoryPlayerLayer(player: video.player)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chrome(_ viewer: StoryViewerState) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(viewer.stories.indices), id: \.self) { index in
                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.35))
                            Capsule().fill(.white).frame(width: bar.size.width * fill(index, viewer))
                        }
                    }
                    .frame(height: 3)
                }
            }
            HStack(spacing: 10) {
                ChatAvatarView(avatar: StoryText.avatar(viewer.ring), size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StoryText.title(viewer.ring, own: viewer.isOwn))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let story = viewer.story {
                        Text(StoryText.ago(story.time, now: Date()))
                            .font(.system(size: 12))
                            .opacity(0.75)
                    }
                }
                Spacer()
                if viewer.isOwn, viewer.story != nil {
                    if viewer.isDeleting {
                        ProgressView().tint(.white).frame(width: 44, height: 44)
                    } else {
                        Button { confirmDelete = true } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Удалить историю")
                    }
                }
                Button { stories.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Закрыть")
            }
            .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func fill(_ index: Int, _ viewer: StoryViewerState) -> Double {
        if index < viewer.storyIndex { return 1 }
        if index > viewer.storyIndex { return 0 }
        return asPhoto ? progress : video.progress
    }

    // MARK: Жесты

    /// Одно касание, удержание и свайпы — одним жестом: так кнопки шапки остаются нажимаемыми.
    private func touchGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil { pressStart = Date() }
                pressing = true
                let t = value.translation
                if abs(t.width) > 10 || abs(t.height) > 10 { drag = t }
            }
            .onEnded { value in
                let held = Date().timeIntervalSince(pressStart ?? Date())
                pressStart = nil
                pressing = false
                let t = value.translation
                drag = .zero
                if abs(t.width) < 10 && abs(t.height) < 10 {
                    // Долгое удержание — пауза, после него история не листается.
                    guard held < 0.25 else { return }
                    if value.location.x < width * 0.32 { stories.previous() } else { stories.next() }
                } else if t.height > 120 && t.height > abs(t.width) {
                    stories.close()
                } else if abs(t.width) > 80 && abs(t.width) > abs(t.height) {
                    if t.width < 0 { stories.nextOwner() } else { stories.previousOwner() }
                }
            }
    }

    // MARK: Запуск истории и таймер

    private struct TimerKey: Hashable {
        let epoch: Int
        let ready: Int
        let holding: Bool
        let asPhoto: Bool
    }

    private func startStory() {
        guard let viewer = stories.viewer, let story = viewer.story, let media = story.media else {
            video.stop()
            return
        }
        let epoch = viewer.epoch
        photo = nil
        video.stop()
        if media.isVideo {
            video.start(url: media.url) { stories.next() }
        }
        let still = media.isVideo ? media.thumbnailURL : media.url
        Task {
            var image: UIImage?
            if let still { image = await ImagePipeline.shared.image(for: still)?.image }
            guard stories.viewer?.epoch == epoch else { return }
            photo = image
            readyEpoch = epoch
        }
    }

    private func runTimer() async {
        guard let viewer = stories.viewer, let story = viewer.story else { return }
        if progressEpoch != viewer.epoch {
            progress = 0
            progressEpoch = viewer.epoch
        }
        guard asPhoto, readyEpoch == viewer.epoch, !holding else { return }
        let length = StoryText.duration(story)
        while progress < 1 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            progress = min(1, progress + 0.05 / length)
        }
        stories.next()
    }
}

/// Видео истории: AVPlayer с User-Agent сессии (CDN выдаёт адреса под Android-клиента).
@MainActor
@Observable
final class StoryVideoPlayback {
    let player = AVPlayer()
    private(set) var progress: Double = 0
    /// Поток не открылся: история показывает обложку по таймеру.
    private(set) var failed = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?

    func start(url: URL, onEnd: @escaping @MainActor () -> Void) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item: AVPlayerItem
        if !url.isFileURL, let agent = MediaHTTP.userAgent {
            item = AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: agent]))
        } else {
            item = AVPlayerItem(url: url)
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error.map { "\($0)" } ?? ""
            Task { @MainActor [weak self] in
                guard let self, status == .failed else { return }
                Log.warning(.media, "Видео истории не воспроизвелось: \(error)")
                self.failed = true
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onEnd() }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem else { return }
                let total = CMTimeGetSeconds(item.duration)
                guard total.isFinite, total > 0 else { return }
                self.progress = min(1, max(0, CMTimeGetSeconds(time) / total))
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func setPaused(_ paused: Bool) {
        guard player.currentItem != nil else { return }
        if paused { player.pause() } else { player.play() }
    }

    func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        progress = 0
        failed = false
    }
}

/// Слой плеера во весь экран, кадр целиком.
struct StoryPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
