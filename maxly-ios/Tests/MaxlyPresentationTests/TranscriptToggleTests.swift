import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

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
        #expect(model.transcripts.canTranscribe(message))
        #expect(model.transcripts.phase(for: clip) == .collapsed)
        model.transcripts.toggle(message)
        #expect(model.transcripts.phase(for: clip) == .expanded)
        model.transcripts.toggle(message)
        #expect(model.transcripts.phase(for: clip) == .collapsed)
    }

    @Test("Неотправленное голосовое расшифровать нельзя")
    func unsent() {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        var message = voice(transcript: nil)
        message.status = .sending
        message.serverId = nil
        #expect(model.transcripts.canTranscribe(message) == false)
    }

    @Test("Ошибка запроса: ошибка раскрыта в пузыре, «^» сворачивает, кнопка снова «→Т»")
    func failed() async {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        let message = voice(transcript: nil)
        let clip = message.content.voices[0]
        model.transcripts.toggle(message)
        #expect(model.transcripts.phase(for: clip) == .loading)
        #expect(await eventually { model.transcripts.phase(for: clip) == .failed })
        #expect(model.errorMessage == nil)
        model.transcripts.toggle(message)
        #expect(model.transcripts.phase(for: clip) == .collapsed)
    }
}
