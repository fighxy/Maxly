import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Расшифровка голосовых: экран")
@MainActor
struct TranscriptToggleTests {
    private func voice(transcript: String?) -> Message {
        Message(
            id: "42", serverId: "42", chatId: "c", authorId: "bob", text: "",
            timestamp: .now, status: .sent,
            content: MessageContent(attachments: [.voice(VoiceContent(id: "900", url: nil, transcript: transcript))])
        )
    }

    @Test("Готовый текст: «→T» раскрывает, «^» сворачивает, сервер не спрашивается")
    func toggleKnown() {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        let message = voice(transcript: "Привет")
        let clip = message.content.voices[0]
        #expect(model.canTranscribe(message))
        #expect(model.transcriptPhase(for: clip) == .collapsed)
        model.toggleTranscript(message)
        #expect(model.transcriptPhase(for: clip) == .expanded)
        model.toggleTranscript(message)
        #expect(model.transcriptPhase(for: clip) == .collapsed)
    }

    @Test("Неотправленное голосовое расшифровать нельзя")
    func unsent() {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        var message = voice(transcript: nil)
        message.status = .sending
        message.serverId = nil
        #expect(model.canTranscribe(message) == false)
    }

    @Test("Ошибка запроса: ошибка раскрыта в пузыре, «^» сворачивает, кнопка снова «→Т»")
    func failed() async {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        let message = voice(transcript: nil)
        let clip = message.content.voices[0]
        model.toggleTranscript(message)
        #expect(model.transcriptPhase(for: clip) == .loading)
        #expect(await eventually { model.transcriptPhase(for: clip) == .failed })
        #expect(model.errorMessage == nil)
        model.toggleTranscript(message)
        #expect(model.transcriptPhase(for: clip) == .collapsed)
    }
}
