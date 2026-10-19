import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

private struct ServiceParts {
    let chats: ChatRepositoryImpl
    let messages: MessageRepositoryImpl
    let sync: SyncEngine
}

private func makeServiceParts(user: String = "1") async throws -> ServiceParts {
    let api = FakeMaxAPI()
    let stack = try SwiftDataStack(inMemory: true)
    let chats = ChatRepositoryImpl.make(stack: stack, api: api)
    let messages = MessageRepositoryImpl.make(stack: stack, api: api)
    let outbox = OutboxQueue(api: api, sleep: { _ in })
    await messages.attach(outbox: outbox)
    let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
    await messages.setCurrentUser(id: user)
    return ServiceParts(chats: chats, messages: messages, sync: sync)
}

private func firstValue<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
    for await value in stream { return value }
    return nil
}

private func row(_ chats: ChatRepositoryImpl, _ id: String) async -> Chat? {
    await firstValue(chats.chats())?.first { $0.id == id }
}

private func groupChat(_ id: String, lastMessageId: String = "m1", preview: String? = "Привет", at seconds: TimeInterval = 100) -> ChatRecord {
    ChatRecord(
        id: id, title: "Дача", type: .group, lastMessageId: lastMessageId, unreadCount: 0,
        updatedAt: Date(timeIntervalSince1970: seconds), preview: preview
    )
}

private func plain(_ id: String, chat: String, author: String, name: String, at seconds: TimeInterval) -> MessageRecord {
    MessageRecord(
        id: id, serverId: id, chatId: chat, authorId: author, text: "Привет",
        timestamp: Date(timeIntervalSince1970: seconds), status: .sent, authorName: name
    )
}

@Suite("Служебные сообщения: база и строка списка")
struct ServiceMessageDataTests {
    @Test("Пуш события: имена участников из базы, текст в строке списка без автора")
    func pushedEvent() async throws {
        let parts = try await makeServiceParts()
        try await parts.chats.upsert([groupChat("g1")])
        try await parts.messages.upsert([plain("m1", chat: "g1", author: "202", name: "Борис", at: 50)])

        await parts.sync.consume(CoreEvent(
            kind: .message, chatId: "g1", messageId: "m2", authorId: "101", text: "", title: "", chatType: "",
            timeMs: 200_000, unread: -1,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"add","userIds":[202,1]}]}"#,
            authorName: "Анна"
        ))

        let stored = try #require(await parts.messages.latest(chatId: "g1")?.domain)
        let notice = try #require(stored.content.service)
        #expect(notice.names?["202"] == "Борис")
        #expect(notice.viewerId == "1")
        #expect(stored.content.isService)
        #expect(ServiceText.text(notice, actorId: stored.authorId, actorName: stored.authorName) == "Анна добавил(а) Борис и вас")

        let chat = try #require(await row(parts.chats, "g1"))
        #expect(chat.preview == "Анна добавил(а) Борис и вас")
        #expect(chat.lastMessage?.media == .service)
    }

    @Test("Строка с сервера без текста берёт событие из сохранённого сообщения")
    func serverRowWithoutText() async throws {
        let parts = try await makeServiceParts()
        try await parts.messages.upsert([MessageRecord(
            id: "m9", serverId: "m9", chatId: "g2", authorId: "1", text: "",
            timestamp: Date(timeIntervalSince1970: 300), status: .sent,
            contentJSON: MessageContentCodec.encode(MessageContentCodec.decode(#"{"attaches":[{"_type":"CONTROL","event":"leave"}]}"#)),
            authorName: "Иван"
        )])
        try await parts.chats.upsert([groupChat("g2", lastMessageId: "m9", preview: nil, at: 300)])

        let chat = try #require(await row(parts.chats, "g2"))
        #expect(chat.preview == "Вы покинули чат")
        #expect(chat.lastMessage?.media == .service)
    }

    @Test("Последнее обычное сообщение строку не трогает")
    func plainRowUntouched() async throws {
        let parts = try await makeServiceParts()
        try await parts.messages.upsert([plain("m5", chat: "g3", author: "101", name: "Анна", at: 100)])
        try await parts.chats.upsert([groupChat("g3", lastMessageId: "m5", preview: nil, at: 100)])
        let chat = try #require(await row(parts.chats, "g3"))
        #expect(chat.preview == nil)
        #expect(chat.lastMessage?.media != .service)
    }

    @Test("Из истории CoreMessage служебное доходит до ленты")
    func fromHistory() {
        let record = CoreMapping.message(CoreMessage(
            id: "7", chatId: "d1", authorId: "101", text: "", timeMs: 1_000,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"hello"}]}"#, authorName: "Анна"
        ))
        let message = record.domain
        #expect(message.content.service?.event == "hello")
        #expect(message.content.previewMedia == .service)
        #expect(ServiceText.text(of: message.content, authorId: message.authorId, authorName: message.authorName) == "Анна теперь в MAX")
    }
}
