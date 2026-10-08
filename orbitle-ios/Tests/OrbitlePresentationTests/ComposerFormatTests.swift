import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Разметка поля ввода")
struct ComposerFormatTests {
    @Test("Жирный ставится на выделение и снимается вторым нажатием")
    func toggle() {
        var format = ComposerFormat()
        format.toggle(.strong, in: 0..<6)
        #expect(format.spans == [TextSpan(kind: .strong, from: 0, length: 6)])
        #expect(format.isActive(.strong, in: 2..<4))
        #expect(!format.isActive(.strong, in: 4..<8))
        format.toggle(.strong, in: 0..<6)
        #expect(format.spans.isEmpty)
    }

    @Test("Набор перед отрезком сдвигает его, на краю — не расширяет, стёртое выпадает")
    func typing() {
        var format = ComposerFormat()
        format.toggle(.emphasized, in: 8..<11)
        format.textChanged(from: "Привет, мир", to: "Ну, привет, мир")
        // «Ну, п» вместо «П»: вставлено 4 символа в начале.
        #expect(format.spans == [TextSpan(kind: .emphasized, from: 12, length: 3)])
        format.textChanged(from: "Ну, привет, мир", to: "Ну, привет, мир!")
        #expect(format.spans == [TextSpan(kind: .emphasized, from: 12, length: 3)])
        format.textChanged(from: "Ну, привет, мир!", to: "")
        #expect(format.spans.isEmpty)
    }

    @Test("Ссылка: адрес без схемы получает https, пустой снимает, мусор не принимается")
    func link() {
        var format = ComposerFormat()
        let accepted = format.setLink("max.ru", in: 0..<4)
        #expect(accepted)
        #expect(format.link(in: 0..<4) == "https://max.ru")
        let rejected = format.setLink("не ссылка", in: 0..<4)
        #expect(!rejected)
        #expect(format.link(in: 0..<4) == "https://max.ru")
        let removed = format.setLink("", in: 0..<4)
        #expect(removed)
        #expect(format.link(in: 0..<4) == nil)
    }

    @Test("«Обычный» снимает разметку панели, упоминание остаётся")
    func clear() {
        var format = ComposerFormat(spans: [
            TextSpan(kind: .strong, from: 0, length: 5),
            TextSpan(kind: .mention, from: 0, length: 5, userId: "7"),
        ])
        #expect(format.hasFormatting(in: 1..<3))
        format.clear(in: 0..<5)
        #expect(format.spans == [TextSpan(kind: .mention, from: 0, length: 5, userId: "7")])
        #expect(!format.hasFormatting(in: 0..<5))
    }
}

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
