import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private final class JoinChats: ChatRepository, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var links: [String] = []
    var fail = false

    func chats() -> AsyncStream<[Chat]> {
        AsyncStream { $0.yield([]); $0.finish() }
    }

    func refresh() async throws(OrbitleError) {}
    func refresh(chatId: String) async throws(OrbitleError) {}
    func markAsRead(chatId: String) async throws(OrbitleError) {}

    func joinByLink(_ link: String) async throws(OrbitleError) -> String? {
        if fail { throw .networkUnavailable }
        lock.withLock { links.append(link) }
        return "c"
    }
}

@Suite("Подписка на канал вне списка")
@MainActor
struct JoinChannelTests {
    @Test("«Подписаться» вступает по публичной ссылке")
    func joinsByLink() async {
        let chats = JoinChats()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), chats: chats)
        let joined = await model.join(link: "https://max.ru/news")
        #expect(joined)
        #expect(chats.links == ["https://max.ru/news"])
        #expect(!model.joining)
    }

    @Test("Отказ сервера показывается, кнопка снова доступна")
    func failureIsShown() async {
        let chats = JoinChats()
        chats.fail = true
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), chats: chats)
        let joined = await model.join(link: "https://max.ru/news")
        #expect(!joined)
        #expect(model.error != nil || model.notice != nil)
        #expect(!model.joining)
    }
}
