import AVFoundation
import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Просмотр историй на весь экран, как в Max. Касание слева (треть ширины) — назад, справа —
/// вперёд, удержание — пауза, свайп вниз — закрыть, вбок — к соседнему владельцу. Фото идёт
/// 5 секунд, видео — сколько длится. В шапке — пауза, звук у видео и «⋯» (профиль, скрыть
/// истории автора, скачать, пожаловаться; у своей — скачать и удалить), внизу — «Ответить» и
/// сердечко. Пока пишется ответ или открыта жалоба, история стоит.
struct StoryViewerView: View {
    let stories: StoriesViewModel
    /// «Перейти в профиль»: экран открывает профиль автора.
    var onProfile: (StoryRing) -> Void = { _ in }
    @State private var paused = false
    @State private var muted = false
    @State private var reply = ""
    @State private var saving = false
    @FocusState private var replyFocused: Bool
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
                        .ignoresSafeArea(.keyboard)
                    chrome(viewer)
                        .ignoresSafeArea(.keyboard)
                    if !viewer.isOwn, let story = viewer.story {
                        replyBar(story)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
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
        .confirmationDialog("Пожаловаться на историю", isPresented: reportShown, titleVisibility: .visible) {
            ForEach(stories.reportReasons ?? []) { reason in
                Button(reason.title) { Task { await stories.report(reason.id) } }
            }
            Button("Отмена", role: .cancel) { stories.closeReport() }
        }
        .onChange(of: stories.viewer?.epoch) { _, _ in
            paused = false
            reply = ""
            startStory()
        }
        .onChange(of: holding) { _, held in video.setPaused(held) }
        .onChange(of: muted) { _, value in video.player.isMuted = value }
        .onAppear { startStory() }
        .onDisappear { video.stop() }
    }

    // MARK: Содержимое

    private var holding: Bool {
        pressing || paused || replyFocused || saving || confirmDelete || stories.reportReasons != nil
            || stories.viewer?.isDeleting == true || drag != .zero
    }

    /// Окно жалобы — когда причины пришли.
    private var reportShown: Binding<Bool> {
        Binding(
            get: { !(stories.reportReasons ?? []).isEmpty },
            set: { if !$0 { stories.closeReport() } }
        )
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
                        .font(.app(size: 15, .semibold))
                        .lineLimit(1)
                    if let story = viewer.story {
                        Text(StoryText.ago(story.time, now: Date()))
                            .font(.app(size: 12))
                            .opacity(0.75)
                    }
                }
                Spacer()
                if viewer.isDeleting || saving || stories.isSending {
                    ProgressView().tint(.white).frame(width: 36, height: 44)
                }
                Button { paused.toggle() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 40, height: 44)
                }
                .accessibilityLabel(paused ? "Смотреть" : "Пауза")
                if viewer.story?.media?.isVideo == true, !video.failed {
                    Button { muted.toggle() } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel(muted ? "Включить звук" : "Выключить звук")
                }
                if let story = viewer.story {
                    moreMenu(viewer, story)
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

    /// «⋯»: чужая история — профиль, скрыть автора, скачать, пожаловаться; своя — скачать и удалить.
    private func moreMenu(_ viewer: StoryViewerState, _ story: Story) -> some View {
        Menu {
            if !viewer.isOwn, story.canOpenProfile {
                Button("Перейти в профиль", systemImage: "person.crop.circle") {
                    let ring = viewer.ring
                    stories.close()
                    onProfile(ring)
                }
            }
            if !viewer.isOwn, story.canHideAuthor {
                Button("Скрыть истории автора", systemImage: "eye.slash") { Task { await stories.hideAuthor() } }
            }
            if viewer.isOwn || story.canDownload {
                Button("Скачать", systemImage: "arrow.down.to.line") { Task { await download(story) } }
            }
            if !viewer.isOwn, story.canReport {
                Button("Пожаловаться", systemImage: "exclamationmark.bubble", role: .destructive) { Task { await stories.openReport() } }
            }
            if viewer.isOwn {
                Button("Удалить", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 44)
        }
        .accessibilityLabel("Ещё")
    }

    /// «Ответить» и сердечко внизу; с текстом сердечко сменяется кнопкой отправки.
    private func replyBar(_ story: Story) -> some View {
        HStack(spacing: 10) {
            if story.canReply {
                TextField("", text: $reply, prompt: Text("Ответить").foregroundStyle(.white.opacity(0.6)))
                    .focused($replyFocused)
                    .submitLabel(.send)
                    .onSubmit(sendReply)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            } else {
                Text("Автор выключил ответы")
                    .font(.app(.footnote))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if story.canReply, !reply.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendReply) {
                    Image(systemName: "paperplane.fill").font(.system(size: 20)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Отправить")
                .disabled(stories.isSending)
            } else if story.canLike {
                Button { Task { await stories.toggleLike() } } label: {
                    Image(systemName: story.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 24))
                        .foregroundStyle(story.isLiked ? Color(red: 1, green: 0.23, blue: 0.36) : .white)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(story.isLiked ? "Убрать лайк" : "Нравится")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func sendReply() {
        let text = reply
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        reply = ""
        replyFocused = false
        Task { await stories.reply(text) }
    }

    /// «Скачать»: файл истории — в «Фото» (фото перекодируется в JPG или PNG).
    private func download(_ story: Story) async {
        guard let media = story.media, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            var request = URLRequest(url: media.url)
            if !media.url.isFileURL, let agent = MediaHTTP.userAgent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
            let (temp, _) = try await URLSession.shared.download(for: request)
            let file = try await StorySaving.savedFile(for: story, downloaded: temp)
            try await PhotoLibrarySaver().save([file])
            stories.message = media.isVideo ? "Видео сохранено в «Фото»" : "Фото сохранено в «Фото»"
        } catch let error as MaxlyError {
            stories.message = error.userMessage ?? "Не удалось сохранить историю"
        } catch {
            Log.warning(.media, "История не скачалась: \(error)")
            stories.message = "Не удалось сохранить историю"
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
