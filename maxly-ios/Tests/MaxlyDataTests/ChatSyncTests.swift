import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

/// База в памяти, репозитории и движок синхронизации без сети и опроса.
private struct SyncParts {
    let api: FakeMaxAPI
    let chats: ChatRepositoryImpl
    let messages: MessageRepositoryImpl
    let sync: SyncEngine
}

private func makeSync(user: String = "me") async throws -> SyncParts {
    let api = FakeMaxAPI()
    let stack = try SwiftDataStack(inMemory: true)
    let chats = ChatRepositoryImpl.make(stack: stack, api: api)
    let messages = MessageRepositoryImpl.make(stack: stack, api: api)
    let outbox = OutboxQueue(api: api, sleep: { _ in })
    await messages.attach(outbox: outbox)
    let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
    await sync.connectOutgoing()
    await messages.setCurrentUser(id: user)
    return SyncParts(api: api, chats: chats, messages: messages, sync: sync)
}

private func event(
    _ kind: CoreEvent.Kind,
    chat: String = "c1",
    message: String = "",
    author: String = "",
    text: String = "",
    title: String = "",
    at seconds: Int64 = 0,
    unread: Int = -1
) -> CoreEvent {
    CoreEvent(kind: kind, chatId: chat, messageId: message, authorId: author, text: text, title: title, chatType: "", timeMs: seconds * 1000, unread: unread)
}

private func row(_ chats: ChatRepositoryImpl, _ id: String = "c1") async -> Chat? {
    await snapshot(chats).first { $0.id == id }
}

@Suite("Список чатов и пуши")
struct ChatSyncTests {
    @Test("Неполный или устаревший пуш чата не затирает строку")
    func upsertMerge() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])

        try await parts.chats.upsert([ChatRecord(id: "c1", title: "", type: .group, unreadCount: 5, updatedAt: Date(timeIntervalSince1970: 200))])
        var chat = try #require(await row(parts.chats))
        #expect(chat.title == "Команда Maxly")
        #expect(chat.preview == "Последнее")
        #expect(chat.lastMessageId == "m99")
        #expect(chat.unreadCount == 5)
        #expect(chat.updatedAt == Date(timeIntervalSince1970: 200))

        try await parts.chats.upsert([ChatRecord(id: "c1", title: "Старое", type: .group, lastMessageId: "m1", unreadCount: 9, updatedAt: Date(timeIntervalSince1970: 0), preview: "Давно")])
        chat = try #require(await row(parts.chats))
        #expect(chat.title == "Старое")
        #expect(chat.preview == "Последнее")
        #expect(chat.lastMessageId == "m99")
        #expect(chat.unreadCount == 5)
        #expect(chat.updatedAt == Date(timeIntervalSince1970: 200))

        try await parts.chats.upsert([ChatRecord(id: "c2", title: "Минус", type: .private, unreadCount: -3, updatedAt: .init(timeIntervalSince1970: 1))])
        #expect(await row(parts.chats, "c2")?.unreadCount == 0)
    }

    @Test("При равном времени чаты упорядочены по id")
    func stableOrder() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat(id: "b"), makeChat(id: "a"), makeChat(id: "c")])
        #expect(await snapshot(parts.chats).map(\.id) == ["a", "b", "c"])
    }

    @Test("Повтор пуша не увеличивает счётчик второй раз, запоздавший не откатывает превью")
    func duplicateAndLatePush() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        let fresh = event(.message, message: "m100", author: "bob", text: "Новое", at: 300)
        await parts.sync.consume(fresh)
        await parts.sync.consume(fresh)
        var chat = try #require(await row(parts.chats))
        #expect(chat.unreadCount == 4)
        #expect(chat.preview == "Новое")

        await parts.sync.consume(event(.message, message: "m50", author: "bob", text: "Запоздало", at: 150))
        chat = try #require(await row(parts.chats))
        #expect(chat.preview == "Новое")
        #expect(chat.lastMessageId == "m100")
        #expect(chat.updatedAt == Date(timeIntervalSince1970: 300))
        #expect(chat.unreadCount == 5)
    }

    @Test("Сообщение в неизвестный чат подтягивает его строку")
    func unknownChat() async throws {
        let parts = try await makeSync()
        await parts.api.setChats([makeChat(id: "new")])
        await parts.sync.consume(event(.message, chat: "new", message: "m1", author: "bob", text: "Привет", at: 50))
        #expect(await parts.api.chatRequests == ["new"])
        #expect(await row(parts.chats, "new") != nil)
    }

    @Test("Прочтение собеседником не трогает наш счётчик")
    func foreignRead() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        await parts.sync.consume(event(.read, author: "bob", at: 500, unread: 0))
        #expect(await row(parts.chats)?.unreadCount == 3)
    }

    @Test("Своя отметка с другого устройства обнуляет счётчик, только если она не раньше последнего сообщения")
    func ownRead() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        await parts.sync.consume(event(.read, author: "me", at: 50, unread: 0))
        #expect(await row(parts.chats)?.unreadCount == 3)
        await parts.sync.consume(event(.read, author: "me", at: 0, unread: 0))
        #expect(await row(parts.chats)?.unreadCount == 3)
        await parts.sync.consume(event(.read, author: "me", at: 100, unread: 0))
        #expect(await row(parts.chats)?.unreadCount == 0)
        await parts.sync.consume(event(.read, author: "me", at: 100, unread: 1))
        #expect(await row(parts.chats)?.unreadCount == 1)
    }

    @Test("Правка меняет превью только у последнего сообщения и не поднимает чат")
    func edits() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat(), ChatRecord(id: "c2", title: "Второй", type: .private, updatedAt: .init(timeIntervalSince1970: 150))])
        try await parts.messages.upsert([
            MessageRecord(id: "m1", serverId: "m1", chatId: "c1", authorId: "bob", text: "Старое", timestamp: .init(timeIntervalSince1970: 10), status: .sent),
        ])

        await parts.sync.consume(event(.edited, message: "m1", author: "bob", text: "Исправлено", at: 10))
        #expect(try await parts.messages.page(chatId: "c1", before: nil).first?.text == "Исправлено")
        #expect(await row(parts.chats)?.preview == "Последнее")
        #expect(await snapshot(parts.chats).map(\.id) == ["c2", "c1"])

        await parts.sync.consume(event(.edited, message: "m99", author: "bob", text: "Последнее, исправлено", at: 100))
        #expect(await row(parts.chats)?.preview == "Последнее, исправлено")
        #expect(try await parts.messages.page(chatId: "c1", before: nil).count == 1)
        #expect(await row(parts.chats)?.unreadCount == 3)
    }

    @Test("Удалили последнее сообщение: превью с сервера, без сети из кэша")
    func deleteLast() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        try await parts.messages.upsert([
            MessageRecord(id: "m98", serverId: "m98", chatId: "c1", authorId: "bob", text: "Предпоследнее", timestamp: .init(timeIntervalSince1970: 90), status: .sent),
            MessageRecord(id: "m99", serverId: "m99", chatId: "c1", authorId: "bob", text: "Последнее", timestamp: .init(timeIntervalSince1970: 100), status: .sent),
        ])
        await parts.api.setChatError(.offline)
        await parts.sync.consume(event(.deleted, message: "m99"))
        var chat = try #require(await row(parts.chats))
        #expect(chat.preview == "Предпоследнее")
        #expect(chat.lastMessageId == "m98")

        await parts.api.setChatError(nil)
        await parts.api.setChats([ChatRecord(id: "c1", title: "Команда Maxly", type: .group, lastMessageId: "m97", updatedAt: .init(timeIntervalSince1970: 100), preview: "С сервера")])
        await parts.sync.consume(event(.deleted, message: "m98"))
        chat = try #require(await row(parts.chats))
        #expect(chat.preview == "С сервера")
        #expect(chat.lastMessageId == "m97")

        await parts.sync.consume(event(.deleted, message: "m1"))
        #expect(await parts.api.chatRequests == ["c1", "c1"])
    }

    @Test("Своё сообщение сдвигает строку сразу, id последнего меняется после ответа сервера")
    func ownMessage() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat(), ChatRecord(id: "c2", title: "Второй", type: .private, updatedAt: .init(timeIntervalSince1970: 150))])
        await parts.api.setSendResults([.failure(.offline)])
        try await parts.messages.send(text: "Отправляю", chatId: "c1")
        var chat = try #require(await row(parts.chats))
        #expect(chat.preview == "Отправляю")
        #expect(chat.lastMessageId == "m99")
        #expect(chat.unreadCount == 3)
        #expect(await snapshot(parts.chats).first?.id == "c1")

        await parts.api.setSendResults([.success(SentMessage(serverId: "srv-9", timestamp: .now))])
        await parts.sync.pollOnce()
        chat = try #require(await row(parts.chats))
        #expect(chat.lastMessageId == "srv-9")

        await parts.sync.consume(event(.message, message: "srv-9", author: "me", text: "Отправляю", at: Int64(Date.now.timeIntervalSince1970)))
        #expect(await row(parts.chats)?.unreadCount == 3)
        #expect(try await parts.messages.page(chatId: "c1", before: nil).count == 1)
    }

    @Test("Нечего читать: отметка на сервер не уходит")
    func markReadSkipsServer() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        try await parts.chats.markAsRead(chatId: "c1")
        try await parts.chats.markAsRead(chatId: "c1")
        #expect(await parts.api.markReadCalls == ["c1"])
    }

    @Test("Пометка «непрочитано»: счётчик сервера, но не меньше одного; ошибка не трогает строку")
    func markUnread() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        try await parts.chats.markAsRead(chatId: "c1")
        try await parts.chats.markUnread(chatId: "c1", from: Date(timeIntervalSince1970: 50))
        #expect(await row(parts.chats)?.unreadCount == 2)

        await parts.api.set(unreadReply: .success(0))
        try await parts.chats.markUnread(chatId: "c1", from: Date(timeIntervalSince1970: 60))
        #expect(await row(parts.chats)?.unreadCount == 1)

        try await parts.chats.markAsRead(chatId: "c1")
        await parts.api.set(unreadReply: .failure(.offline))
        await #expect(throws: MaxlyError.self) {
            try await parts.chats.markUnread(chatId: "c1", from: Date(timeIntervalSince1970: 70))
        }
        #expect(await row(parts.chats)?.unreadCount == 0)
        #expect(await parts.api.markUnreadCalls == ["c1", "c1", "c1"])
    }

    @Test("Удаление чата забирает и сообщения, записанные раньше чата")
    func deleteChatWithOrphans() async throws {
        let parts = try await makeSync()
        try await parts.messages.upsert([
            MessageRecord(id: "o1", serverId: "o1", chatId: "c1", authorId: "bob", text: "Раньше чата", timestamp: .init(timeIntervalSince1970: 1), status: .sent),
        ])
        try await parts.chats.upsert([makeChat()])
        try await parts.chats.delete(chatId: "c1")
        #expect(try await parts.messages.page(chatId: "c1", before: nil).isEmpty)
        #expect(await row(parts.chats) == nil)
    }

    @Test("Полный список сервера убирает чаты, которых в нём нет; неполный — нет; «Избранное» остаётся")
    func completeListDropsChatsLeftElsewhere() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat(id: "keep"), makeChat(id: "left"), makeChat(id: Chat.savedMessagesId)])
        try await parts.messages.upsert([
            MessageRecord(id: "m1", serverId: "m1", chatId: "left", authorId: "bob", text: "Пост", timestamp: .init(timeIntervalSince1970: 2), status: .sent),
        ])
        await parts.api.setChats([makeChat(id: "keep")])

        try await parts.chats.refresh()
        #expect(await row(parts.chats, "left") != nil)

        await parts.api.setChatListComplete(true)
        try await parts.chats.refresh()
        #expect(await row(parts.chats, "keep") != nil)
        #expect(await row(parts.chats, "left") == nil)
        #expect(await row(parts.chats, Chat.savedMessagesId) != nil)
        #expect(try await parts.messages.page(chatId: "left", before: nil).isEmpty)
    }

    @Test("Неактивный чат (вышел, закрыт) уходит из списка: при обновлении и по пушу")
    func inactiveChatsLeaveTheList() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat(), makeChat(id: "c2")])
        var gone = makeChat()
        gone.isActive = false
        await parts.api.setChats([gone, makeChat(id: "c2")])
        try await parts.chats.refresh()
        #expect(await row(parts.chats) == nil)
        #expect(await row(parts.chats, "c2") != nil)

        await parts.sync.consume(event(.chatGone, chat: "c2"))
        #expect(await row(parts.chats, "c2") == nil)
    }

    @Test("Отписка от канала уходит на сервер и убирает чат с историей; отказ оставляет его")
    func leaveChannel() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        try await parts.messages.upsert([
            MessageRecord(id: "m1", serverId: "m1", chatId: "c1", authorId: "bob", text: "Пост", timestamp: .init(timeIntervalSince1970: 2), status: .sent),
        ])
        await parts.api.set(chatLeaveResult: .failure(.offline))
        await #expect(throws: MaxlyError.self) {
            try await parts.chats.leave(chatId: "c1")
        }
        #expect(await row(parts.chats) != nil)

        await parts.api.set(chatLeaveResult: .success(()))
        try await parts.chats.leave(chatId: "c1")
        #expect(await parts.api.chatLeaves == ["c1", "c1"])
        #expect(await row(parts.chats) == nil)
        #expect(try await parts.messages.page(chatId: "c1", before: nil).isEmpty)
    }

    @Test("Удаление чата и очистка истории уходят на сервер и правят локальную строку")
    func deleteAndClearReachTheServer() async throws {
        let parts = try await makeSync()
        try await parts.chats.upsert([makeChat()])
        try await parts.messages.upsert([
            MessageRecord(id: "m1", serverId: "m1", chatId: "c1", authorId: "bob", text: "Живое", timestamp: .init(timeIntervalSince1970: 2), status: .sent),
        ])

        try await parts.chats.clearHistory(chatId: "c1", forEveryone: false)
        let clears = await parts.api.historyClears
        #expect(clears.map(\.0) == ["c1"])
        #expect(clears.map(\.1) == [Int64(100_000)])
        #expect(clears.map(\.2) == [false])
        let kept = try #require(await row(parts.chats))
        #expect(kept.preview == nil)
        #expect(kept.lastMessageId == nil)
        #expect(kept.unreadCount == 0)
        #expect(try await parts.messages.page(chatId: "c1", before: nil).isEmpty)

        try await parts.chats.delete(chatId: "c1", forEveryone: true)
        let deletes = await parts.api.chatDeletes
        #expect(deletes.map(\.0) == ["c1"])
        #expect(deletes.map(\.1) == [Int64(100_000)])
        #expect(deletes.map(\.2) == [true])
        #expect(await row(parts.chats) == nil)
    }
}
