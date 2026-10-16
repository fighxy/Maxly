import SwiftUI
import MaxlyDomain

private struct GifAutoplayKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// Можно ли сейчас автоматически играть гифки в ленте (настройка и сеть).
    /// Приложение кладёт сюда решение `GifAutoplayPolicy`.
    var gifAutoplay: Bool {
        get { self[GifAutoplayKey.self] }
        set { self[GifAutoplayKey.self] = newValue }
    }
}

#if canImport(UIKit)
import AVFoundation
import UIKit

/// Плееры гифок: один на адрес ролика, не больше `capacity`. Плитка на экране берёт плеер,
/// ушедшая с экрана — ставит на паузу и отдаёт обратно; давно не нужные освобождаются.
@MainActor
final class GifPlayerPool {
    static let shared = GifPlayerPool()

    private final class Entry {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        var users = 0
        var lastUse = Date()

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.automaticallyWaitsToMinimizeStalling = true
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
    }

    private var entries: [URL: Entry] = [:]
    private let capacity = 6

    func acquire(_ url: URL) -> AVQueuePlayer {
        let entry = entries[url] ?? {
            let made = Entry(url: url)
            entries[url] = made
            return made
        }()
        entry.users += 1
        entry.lastUse = Date()
        trim()
        return entry.player
    }

    func release(_ url: URL) {
        guard let entry = entries[url] else { return }
        entry.users = max(0, entry.users - 1)
        entry.lastUse = Date()
        if entry.users == 0 { entry.player.pause() }
        trim()
    }

    private func trim() {
        guard entries.count > capacity else { return }
        let idle = entries.filter { $0.value.users == 0 }.sorted { $0.value.lastUse < $1.value.lastUse }
        for (url, entry) in idle.prefix(entries.count - capacity) {
            entry.player.pause()
            entry.player.removeAllItems()
            entries[url] = nil
        }
    }
}

/// Гифка в ленте: ролик MP4 без звука по кругу. Играет только пока видна в окне;
/// до первого кадра под ней видна статичная картинка.
struct GifLoopView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> GifLoopUIView {
        GifLoopUIView(url: url)
    }

    func updateUIView(_ view: GifLoopUIView, context: Context) {
        view.setURL(url)
    }

    static func dismantleUIView(_ view: GifLoopUIView, coordinator: ()) {
        view.detach()
    }
}

final class GifLoopUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var url: URL
    private var attached: URL?
    private var readyObservation: NSKeyValueObservation?

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setURL(_ next: URL) {
        guard next != url else { return }
        detach()
        url = next
        if window != nil { attach() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { attach() } else { detach() }
    }

    private func attach() {
        guard attached == nil else { return }
        let player = GifPlayerPool.shared.acquire(url)
        attached = url
        playerLayer.player = player
        // Картинка остаётся видна, пока ролик не дал первый кадр.
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor [weak self] in
                guard let self, self.attached != nil else { return }
                self.playerLayer.opacity = ready ? 1 : 0
            }
        }
        player.play()
    }

    func detach() {
        guard let attached else { return }
        readyObservation = nil
        playerLayer.player = nil
        playerLayer.opacity = 0
        self.attached = nil
        GifPlayerPool.shared.release(attached)
    }
}
#endif
