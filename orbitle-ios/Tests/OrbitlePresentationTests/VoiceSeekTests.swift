import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Перемотка голосового: палец → доля")
struct WaveformSeekMappingTests {
    @Test("Доля — расстояние от левого края дорожки, за краями — 0 и 1")
    func mapping() {
        let layout = WaveformLayout(width: 200)
        #expect(layout.progress(atX: 0) == 0)
        #expect(layout.progress(atX: 50) == 0.25)
        #expect(layout.progress(atX: 100) == 0.5)
        #expect(layout.progress(atX: 200) == 1)
        #expect(layout.progress(atX: -30) == 0)
        #expect(layout.progress(atX: 260) == 1)
        #expect(layout.progress(atX: .nan) == 0)
        #expect(WaveformLayout(width: 0).progress(atX: 10) == 0)
    }

    @Test("Граница закраски идёт прямо под пальцем")
    func boundaryUnderFinger() {
        let layout = WaveformLayout(width: 241)
        for index in [0, 7, layout.count / 2, layout.count - 2] {
            // Палец на середине столбика: он закрашен, следующий — нет.
            let middle = layout.x(of: index) + layout.barWidth / 2
            let progress = layout.progress(atX: middle)
            #expect(layout.isPlayed(index, progress: progress))
            #expect(!layout.isPlayed(index + 1, progress: progress))
        }
        // Палец у самого правого края закрашивает всю дорожку.
        let end = layout.progress(atX: 241)
        #expect((0..<layout.count).allSatisfy { layout.isPlayed($0, progress: end) })
    }
}

@MainActor
private final class FakeVoicePlayer: VoicePlaying {
    private(set) var played: [URL] = []
    private(set) var seeks: [Double] = []
    private(set) var resumes = 0
    var progress: Double = 0
    var isPlaying = false
    var failed = false

    func play(url: URL) -> Bool {
        played.append(url)
        progress = 0
        isPlaying = true
        return true
    }

    func pause() { isPlaying = false }

    func resume() -> Bool {
        resumes += 1
        isPlaying = true
        return true
    }

    func stop() { isPlaying = false }

    func seek(to fraction: Double) {
        seeks.append(fraction)
        progress = fraction
    }
}

@Suite("Перемотка голосового: плеер")
@MainActor
struct VoiceSeekTests {
    private func voiceMessage() throws -> Message {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("seek-\(UUID().uuidString).ogg")
        try Data([0x4F, 0x67, 0x67, 0x53]).write(to: file)
        let voice = VoiceContent(id: "v1", url: nil, durationMs: 10_000, localPath: file.path)
        return Message(
            id: "m1", chatId: "c", authorId: "2", text: "",
            timestamp: Date(timeIntervalSince1970: 1), status: .sent,
            content: MessageContent(attachments: [.voice(voice)])
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    @Test("Не начатое голосовое начинает играть с места под пальцем")
    func seekStartsPlayback() async throws {
        let player = FakeVoicePlayer()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), voice: player)
        let message = try voiceMessage()

        model.seekVoice(message, to: 0.4)
        await waitUntil { !player.played.isEmpty }
        #expect(player.played.count == 1)
        #expect(player.seeks == [0.4])
        #expect(model.voicePhase(for: "v1") == .playing(0.4))
        model.stopVoice()
    }

    @Test("Играющее продолжает с нового места, без нового запуска")
    func seekWhilePlaying() async throws {
        let player = FakeVoicePlayer()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), voice: player)
        let message = try voiceMessage()
        model.toggleVoice(message)
        await waitUntil { !player.played.isEmpty }
        #expect(model.voicePhase(for: "v1").isPlaying)

        model.seekVoice(message, to: 0.75)
        #expect(player.played.count == 1)
        #expect(player.seeks == [0.75])
        #expect(model.voicePhase(for: "v1") == .playing(0.75))
        model.stopVoice()
    }

    @Test("С паузы перемотка продолжает играть с нового места")
    func seekWhilePaused() async throws {
        let player = FakeVoicePlayer()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), voice: player)
        let message = try voiceMessage()
        model.toggleVoice(message)
        await waitUntil { !player.played.isEmpty }
        model.toggleVoice(message)
        await waitUntil { !model.voicePhase(for: "v1").isPlaying }
        guard case .paused = model.voicePhase(for: "v1") else {
            Issue.record("голосовое не встало на паузу")
            return
        }

        model.seekVoice(message, to: 0.2)
        #expect(player.resumes == 1)
        #expect(player.played.count == 1)
        #expect(player.seeks == [0.2])
        #expect(model.voicePhase(for: "v1") == .playing(0.2))
        model.stopVoice()
    }

    @Test("Доля за пределами 0…1 прижимается к краю")
    func clamps() async throws {
        let player = FakeVoicePlayer()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), voice: player)
        let message = try voiceMessage()
        model.seekVoice(message, to: 1.7)
        await waitUntil { !player.played.isEmpty }
        #expect(player.seeks == [1])
        model.seekVoice(message, to: -0.3)
        #expect(player.seeks == [1, 0])
        #expect(model.voicePhase(for: "v1") == .playing(0))
        model.stopVoice()
    }
}
