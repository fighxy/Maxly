import AVFoundation
import Foundation
import OrbitlePresentation

/// Системный плеер голосовых. Сначала `AVAudioPlayer`, затем `AVPlayer`.
/// Opus система может не открыть: тогда фаза на пузыре становится ошибкой.
@MainActor
final class SystemVoicePlayer: VoicePlaying {
    private var audio: AVAudioPlayer?
    private var player: AVPlayer?

    func play(url: URL) -> Bool {
        stop()
        prepareSession()
        if let audio = try? AVAudioPlayer(contentsOf: url), audio.prepareToPlay(), audio.play() {
            self.audio = audio
            return true
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
        return item.status != .failed && player.status != .failed
    }

    func pause() {
        audio?.pause()
        player?.pause()
    }

    func resume() -> Bool {
        if let audio { return audio.play() }
        guard let player else { return false }
        player.play()
        return player.currentItem?.status != .failed
    }

    func stop() {
        audio?.stop()
        audio = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    var progress: Double {
        if let audio, audio.duration > 0 {
            return min(max(audio.currentTime / audio.duration, 0), 1)
        }
        guard let item = player?.currentItem else { return 0 }
        let duration = item.duration.seconds
        let time = item.currentTime().seconds
        guard duration.isFinite, duration > 0, time.isFinite else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    var isPlaying: Bool {
        if let audio { return audio.isPlaying }
        switch player?.timeControlStatus {
        case .playing, .waitingToPlayAtSpecifiedRate:
            return true
        default:
            return false
        }
    }

    var failed: Bool {
        if audio != nil { return false }
        return player?.status == .failed || player?.currentItem?.status == .failed
    }

    private func prepareSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }
}
