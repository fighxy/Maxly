import AVFoundation
import Foundation
import MaxlyData
import MaxlyDomain
import MaxlyPresentation

/// Системный плеер голосовых. Сначала `AVAudioPlayer`, затем `AVPlayer`.
///
/// Голосовые Max — Opus в контейнере Ogg, который системные плееры не открывают. Такой файл
/// один раз перекладывается в CAF рядом с исходным (`OggOpus`), и играет уже CAF.
@MainActor
final class SystemVoicePlayer: VoicePlaying {
    private var audio: AVAudioPlayer?
    private var player: AVPlayer?

    func play(url source: URL) -> Bool {
        stop()
        prepareSession()
        let (url, hint) = Self.playable(source)
        do {
            let audio = try AVAudioPlayer(contentsOf: url, fileTypeHint: hint)
            if audio.prepareToPlay(), audio.play() {
                self.audio = audio
                return true
            }
            Log.warning(.media, "Голосовое не запустилось (\(hint ?? "без типа"))")
        } catch {
            Log.warning(.media, "Голосовое не открылось (\(hint ?? "без типа")): \(error)")
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

    func seek(to fraction: Double) {
        let fraction = min(max(fraction, 0), 1)
        if let audio {
            audio.currentTime = audio.duration * fraction
            return
        }
        guard let player, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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

    /// Файл, который откроет `AVAudioPlayer`, и подсказка типа по первым байтам.
    static func playable(_ url: URL) -> (URL, String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (url, nil) }
        let head = [UInt8]((try? handle.read(upToCount: 12)) ?? Data())
        try? handle.close()
        if head.starts(with: Array("OggS".utf8)) {
            let caf = url.appendingPathExtension("caf")
            if FileManager.default.fileExists(atPath: caf.path) { return (caf, AVFileType.caf.rawValue) }
            do {
                let data = try Data(contentsOf: url)
                try OggOpus.caf(fromOgg: data).write(to: caf, options: .atomic)
                return (caf, AVFileType.caf.rawValue)
            } catch {
                Log.warning(.media, "Ogg не переложился в CAF: \(error)")
                return (url, nil)
            }
        }
        if head.count >= 8, Array(head[4..<8]) == Array("ftyp".utf8) { return (url, AVFileType.m4a.rawValue) }
        if head.starts(with: Array("caff".utf8)) { return (url, AVFileType.caf.rawValue) }
        if head.starts(with: Array("RIFF".utf8)) { return (url, AVFileType.wav.rawValue) }
        if head.starts(with: Array("ID3".utf8)) || (head.first == 0xFF && (head.dropFirst().first ?? 0) & 0xE0 == 0xE0) {
            return (url, AVFileType.mp3.rawValue)
        }
        return (url, nil)
    }

    private func prepareSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }
}
