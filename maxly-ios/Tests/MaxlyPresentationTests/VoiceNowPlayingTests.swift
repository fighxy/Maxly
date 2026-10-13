import Foundation
import Testing
@testable import MaxlyPresentation

@MainActor
private final class Owner: VoiceNowPlayingOwner {
    var calls: [String] = []
    func nowPlayingToggle() { calls.append("toggle") }
    func nowPlayingStop() { calls.append("stop") }
    func nowPlayingReleased() { calls.append("released") }
}

@Suite("Полоса «играет голосовое»")
@MainActor
struct VoiceNowPlayingTests {
    private func track(_ chat: String, playing: Bool = true) -> VoiceNowPlaying.Track {
        VoiceNowPlaying.Track(chatId: chat, messageId: "m", author: "", date: nil, progress: 0.25, durationMs: 40_000, isPlaying: playing)
    }

    @Test("Скорость по кругу и в плеер")
    func speed() {
        let model = VoiceNowPlaying()
        var applied: [Float] = []
        model.applySpeed = { applied.append($0) }
        model.cycleSpeed()
        model.cycleSpeed()
        model.cycleSpeed()
        #expect(applied == [1.5, 2, 1])
        #expect(VoiceNowPlaying.speeds.map(VoiceNowPlaying.label) == ["1x", "1.5x", "2x"])
    }

    @Test("Новый чат забирает полосу, прежний отпускает плеер")
    func claim() {
        let model = VoiceNowPlaying()
        let first = Owner()
        let second = Owner()
        model.claim(first, track: track("1"))
        model.claim(second, track: track("2"))
        #expect(first.calls == ["released"])
        // Чужие обновления не трогают полосу.
        model.update(first, track: track("1", playing: false))
        model.clear(first)
        #expect(model.track?.chatId == "2")
        #expect(model.track?.title == "Голосовое сообщение")
        #expect(model.track?.timeText == "0:10 / 0:40")
        model.toggle()
        model.stop()
        #expect(second.calls == ["toggle", "stop"])
        #expect(model.track == nil)
    }
}
