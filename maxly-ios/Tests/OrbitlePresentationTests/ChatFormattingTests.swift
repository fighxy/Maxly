import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Репозиторий, который записывает отправку и правку с разметкой.
private actor FormattedMessages: MessageRepository {
    struct Sent: Equatable {
        var text: String
        var formatting: [TextSpan]
    }

    private(set) var sent: [Sent] = []
    private(set) var edits: [Sent] = []

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { $0.finish() } }
    func loadOlder(chatId: String) async throws(OrbitleError) {}
    func loadMore(chatId: String, before: Date?) async throws(OrbitleError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(OrbitleError) {}
    func retry(messageId: String) async throws(OrbitleError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(OrbitleError) {
        sent.append(Sent(text: text, formatting: []))
    }
    func send(text: String, chatId: String, replyTo: String?, formatting: [TextSpan]) async throws(OrbitleError) {
        sent.append(Sent(text: text, formatting: formatting))
    }
    func edit(messageId: String, chatId: String, text: String, formatting: [TextSpan]) async throws(OrbitleError) {
        edits.append(Sent(text: text, formatting: formatting))
    }
    func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) {}
    func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(OrbitleError) {}
}

@Suite("Экран чата: разметка при отправке и правке")
@MainActor
struct ChatFormattingTests {
    @Test("Выделенное уходит с разметкой по обрезанному тексту")
    func sendFormatted() async {
        let repo = FormattedMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repo)
        model.draft = "  Привет, мир"
        model.formatSelection = 10..<13
        model.toggleFormat(.strong)
        #expect(model.isFormatActive(.strong))
        await model.send()
        #expect(await repo.sent == [.init(text: "Привет, мир", formatting: [TextSpan(kind: .strong, from: 8, length: 3)])])
        #expect(model.format.spans.isEmpty)
    }

    @Test("Правка уходит со всем списком разметки; снятая разметка — пустым списком")
    func editFormatted() async {
        let repo = FormattedMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repo)
        let bold = TextSpan(kind: .strong, from: 0, length: 6)
        let message = Message(id: "m1", serverId: "77", chatId: "c", authorId: "me", text: "Привет, мир",
                              timestamp: .now, status: .sent, content: MessageContent(formatting: [bold]))
        model.beginEdit(message)
        #expect(model.format.spans == [bold])
        // Без изменений правка закрывается без запроса.
        await model.send()
        #expect(await repo.edits.isEmpty)
        #expect(model.editTarget == nil)

        model.beginEdit(message)
        model.formatSelection = 0..<6
        model.toggleFormat(.strong)
        await model.send()
        #expect(await repo.edits == [.init(text: "Привет, мир", formatting: [])])
    }
}
