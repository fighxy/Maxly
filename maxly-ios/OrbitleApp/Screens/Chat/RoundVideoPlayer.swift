import AVFoundation
import SwiftUI
import OrbitleDomain
import UIKit

/// Кружок, играющий прямо в ленте: ролик со звуком в круге и кольцо
/// прогресса по краю. Доиграв, возвращает пузырь к кадру-обложке (`onEnd`).
struct RoundVideoPlayer: View {
    let url: URL
    let onEnd: @MainActor () -> Void
    @State private var playback = RoundPlayerState()

    var body: some View {
        ZStack {
            RoundPlayerLayer(player: playback.player)
            Circle()
                .trim(from: 0, to: playback.progress)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            if playback.loading {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .allowsHitTesting(false)
        .onAppear { playback.start(url: url, onEnd: onEnd) }
        .onDisappear { playback.stop() }
    }
}

@MainActor
@Observable
private final class RoundPlayerState {
    let player = AVPlayer()
    private(set) var progress: Double = 0
    private(set) var loading = true
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
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.loading = false
                case .failed:
                    Log.warning(.media, "Кружок не воспроизвёлся: \(error)")
                    onEnd()
                default:
                    break
                }
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

    func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        progress = 0
        loading = true
    }
}

/// Слой плеера, заполняющий квадрат кружка.
private struct RoundPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
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
