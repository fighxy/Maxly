import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Строка чата, где последнее сообщение отправлено в `sentMs`, а время чата (`updatedAt`)
/// позже: после сообщения были правка или реакция.
private func chatRecord(
    unread: Int = 3,
    sentMs: Int64 = 100_000,
    updatedAt: TimeInterval = 150,
    outgoing: Bool = false,
    peerReadMark: Int64 = 0
) -> ChatRecord {
    ChatRecord(
        id: "c1",
        title: "Аня",
        type: .private,
        lastMessageId: "m99",
        unreadCount: unread,
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        preview: "Последнее",
        lastAuthorId: outgoing ? "me" : "anya",
        lastOutgoing: outgoing,
        peerReadMark: peerReadMark,
        lastMessageAt: sentMs
    )
}

private func makeRepository() throws -> (ChatRepositoryImpl, FakeMaxAPI) {
    let api = FakeMaxAPI()
    let stack = try SwiftDataStack(inMemory: true)
    return (ChatRepositoryImpl.make(stack: stack, api: api), api)
}

private func row(_ chats: ChatRepositoryImpl) async -> Chat? {
    await snapshot(chats).first { $0.id == "c1" }
}

@Suite("Отметки прочтения: правила")
struct ReadMarksRuleTests {
    @Test("Отметки сравниваются со временем сообщения, а без него — со временем чата")
    func readTime() {
        #expect(ReadMarks.readTime(lastMessageAt: 100_000, updatedAt: Date(timeIntervalSince1970: 150)) == 100_000)
        #expect(ReadMarks.readTime(lastMessageAt: 0, updatedAt: Date(timeIntervalSince1970: 150)) == 150_000)
    }

    @Test("Собеседник прочитал всё, что отправлено не позже его отметки")
    func peerRead() {
        #expect(ReadMarks.isReadByPeer(peerMark: 100_000, messageTime: 100_000))
        #expect(ReadMarks.isReadByPeer(peerMark: 120_000, messageTime: 100_000))
        #expect(!ReadMarks.isReadByPeer(peerMark: 90_000, messageTime: 100_000))
        #expect(!ReadMarks.isReadByPeer(peerMark: 0, messageTime: 0))
    }

    @Test("Ответ старее применённой отметки не свежий")
    func fresh() {
        #expect(ReadMarks.isFresh(500, known: 0))
        #expect(ReadMarks.isFresh(500, known: 500))
        #expect(!ReadMarks.isFresh(400, known: 500))
        #expect(!ReadMarks.isFresh(0, known: 0))
    }

    @Test("Счётчик сервера берётся, только если он меньше и новых сообщений не было")
    func unreadAfterRead() {
        #expect(ReadMarks.unreadAfterRead(local: 3, lastNow: "m1", lastBefore: "m1", server: 0) == 0)
        #expect(ReadMarks.unreadAfterRead(local: 0, lastNow: "m1", lastBefore: "m1", server: 2) == nil)
        #expect(ReadMarks.unreadAfterRead(local: 3, lastNow: "m2", lastBefore: "m1", server: 0) == nil)
        #expect(ReadMarks.unreadAfterRead(local: 3, lastNow: "m1", lastBefore: "m1", server: -1) == nil)
    }
}

@Suite("Отметки прочтения: чат")
struct ReadStatusTests {
    @Test("Отметка уходит временем последнего сообщения, а не часами устройства")
    func markUsesMessageTime() async throws {
        let (chats, api) = try makeRepository()
        try await chats.upsert([chatRecord(sentMs: 1_700_000_000_500)])
        try await chats.markAsRead(chatId: "c1")
        #expect(await api.readMarks == [1_700_000_000_500])

        // Пуш нового сообщения несёт время сервера: следующая отметка — с ним.
        _ = try await chats.noteMessage(
            chatId: "c1", messageId: "m100", preview: "Ещё", at: Date(unixMillis: 1_700_000_000_900), incoming: true
        )
        try await chats.markAsRead(chatId: "c1")
        #expect(await api.readMarks == [1_700_000_000_500, 1_700_000_000_900])
    }

    @Test("Ответ сервера применяется сразу, запоздавший ответ на старую отметку — нет")
    func replyApplied() async throws {
        let (chats, _) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 3)])
        try await chats.applyReadReply(chatId: "c1", reply: CoreReadMark(unread: 1, mark: 500), lastBefore: "m99")
        #expect(await row(chats)?.unreadCount == 1)

        try await chats.applyReadReply(chatId: "c1", reply: CoreReadMark(unread: 0, mark: 400), lastBefore: "m99")
        #expect(await row(chats)?.unreadCount == 1)

        // Со времени отметки пришло новое сообщение: оно остаётся непрочитанным.
        try await chats.applyReadReply(chatId: "c1", reply: CoreReadMark(unread: 0, mark: 600), lastBefore: "m98")
        #expect(await row(chats)?.unreadCount == 1)

        try await chats.applyReadReply(chatId: "c1", reply: CoreReadMark(unread: 0, mark: 600), lastBefore: "m99")
        #expect(await row(chats)?.unreadCount == 0)
    }

    @Test("Ответ сервера не поднимает счётчик выше локального")
    func replyNeverRaises() async throws {
        let (chats, api) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 2)])
        await api.set(readReplies: [CoreReadMark(unread: 5, mark: 100_000)])
        try await chats.markAsRead(chatId: "c1")
        #expect(await row(chats)?.unreadCount == 0)
    }

    @Test("Своя отметка с другого устройства снимает бейдж, даже если после сообщения была реакция")
    func ownReadAfterReaction() async throws {
        let (chats, _) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 3, sentMs: 100_000, updatedAt: 150)])
        try await chats.applyOwnRead(chatId: "c1", mark: 99_000, setAsUnread: false)
        #expect(await row(chats)?.unreadCount == 3)
        try await chats.applyOwnRead(chatId: "c1", mark: 100_000, setAsUnread: false)
        #expect(await row(chats)?.unreadCount == 0)
    }

    @Test("Две галочки в строке по времени своего сообщения, а не по времени чата")
    func rowReadByMessageTime() async throws {
        let (chats, _) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 0, sentMs: 100_000, updatedAt: 150, outgoing: true, peerReadMark: 90_000)])
        #expect(await row(chats)?.lastMessage?.delivery == .sent)

        // Отметка из карточки чата.
        try await chats.upsert([chatRecord(unread: 0, sentMs: 100_000, updatedAt: 150, outgoing: true, peerReadMark: 120_000)])
        #expect(await row(chats)?.lastMessage?.delivery == .read)
    }

    @Test("Пуш прочтения собеседником ставит две галочки сразу, старая карточка их не снимает")
    func rowReadByPush() async throws {
        let (chats, _) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 0, sentMs: 100_000, updatedAt: 150, outgoing: true, peerReadMark: 90_000)])
        try await chats.applyPeerRead(chatId: "c1", mark: 100_000)
        #expect(await row(chats)?.lastMessage?.delivery == .read)

        try await chats.upsert([chatRecord(unread: 0, sentMs: 100_000, updatedAt: 150, outgoing: true, peerReadMark: 90_000)])
        #expect(await row(chats)?.lastMessage?.delivery == .read)
    }

    @Test("Отправленное после отметки собеседника — одна галочка")
    func rowSentAfterMark() async throws {
        let (chats, _) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 0, sentMs: 100_000, updatedAt: 150, outgoing: true, peerReadMark: 100_000)])
        try await chats.noteSent(chatId: "c1", localId: "l1", serverId: "m100", preview: "Новое",
                                 at: Date(unixMillis: 160_000), authorId: "me")
        #expect(await row(chats)?.lastMessage?.delivery == .sent)
        try await chats.applyPeerRead(chatId: "c1", mark: 160_000)
        #expect(await row(chats)?.lastMessage?.delivery == .read)
    }
}

@Suite("Отметки прочтения: клиент ядра")
struct ReadMarkClientTests {
    @Test("Время сообщения доходит до ядра, ответ возвращается")
    func passesMark() async {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        let skipped = await client.markRead(chatId: "1", messageId: nil, at: 5)
        #expect(skipped == .success(nil))
        #expect(await core.readAt.isEmpty)

        let reply = await client.markRead(chatId: "1", messageId: "55", at: 1_700_000_000_123)
        #expect(reply == .success(CoreReadMark(unread: 0, mark: 1_700_000_000_123)))
        #expect(await core.readAt == [1_700_000_000_123])

        // Время неизвестно: ядро ищет его само, ответ без отметки не применяется.
        let unknown = await client.markRead(chatId: "1", messageId: "56", at: 0)
        #expect(unknown == .success(nil))
        #expect(await core.readAt == [1_700_000_000_123, 0])
    }
}

@Suite("Отметки прочтения: экран чата")
struct ScreenReadMarkTests {
    @Test("Отметка до последнего сообщения уходит с его временем и снимает бейдж сразу")
    func markUpToLast() async throws {
        let (chats, api) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 3, sentMs: 100_000)])
        try await chats.markRead(chatId: "c1", messageId: "m99", at: 100_000)
        #expect(await api.readMarks == [100_000])
        #expect(await row(chats)?.unreadCount == 0)
    }

    @Test("Отметка ниже последнего: бейдж не пропадает, счётчик — из ответа сервера")
    func markPartway() async throws {
        let (chats, api) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 3, sentMs: 100_000)])
        await api.set(readReplies: [CoreReadMark(unread: 1, mark: 90_000)])
        try await chats.markRead(chatId: "c1", messageId: "m98", at: 90_000)
        #expect(await api.readMarks == [90_000])
        #expect(await row(chats)?.unreadCount == 1)
    }

    @Test("Непрочитанных нет — сервер не дёргается")
    func nothingToRead() async throws {
        let (chats, api) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 0, sentMs: 100_000)])
        try await chats.markRead(chatId: "c1", messageId: "m99", at: 100_000)
        try await chats.markRead(chatId: "unknown", messageId: "m1", at: 100_000)
        #expect(await api.readMarks.isEmpty)
    }
}

@Suite("Своя позиция чата: репозиторий")
struct OwnReadMarkDataTests {
    @Test("Своя позиция — самая свежая из ответа сервера, пуша и местной отметки ядра")
    func ownPositionIsNewest() async throws {
        let (chats, api) = try makeRepository()
        try await chats.upsert([chatRecord(unread: 3, sentMs: 100_000)])
        #expect(chats.ownReadMark(chatId: "c1") == 0)

        await api.set(readReplies: [CoreReadMark(unread: 2, mark: 50_000)])
        try await chats.markRead(chatId: "c1", messageId: "m50", at: 50_000)
        #expect(chats.ownReadMark(chatId: "c1") == 50_000)

        try await chats.applyOwnRead(chatId: "c1", mark: 70_000, setAsUnread: false)
        #expect(chats.ownReadMark(chatId: "c1") == 70_000)

        // Отметки о прочтении скрыты: ядро читает чат только на устройстве.
        let local = LocalMarks()
        chats.setLocalReadMarks { local.mark(of: $0) }
        local.set(90_000, for: "c1")
        #expect(chats.ownReadMark(chatId: "c1") == 90_000)
        #expect(chats.ownReadMark(chatId: "other") == 0)

        // Пометка «непрочитано» забывает отметки сервера; местная остаётся у ядра.
        try await chats.applyOwnRead(chatId: "c1", mark: 0, setAsUnread: true)
        local.set(0, for: "c1")
        #expect(chats.ownReadMark(chatId: "c1") == 0)
    }
}

/// Местные отметки ядра в тесте.
private final class LocalMarks: @unchecked Sendable {
    private let lock = NSLock()
    private var marks: [String: Int64] = [:]

    func set(_ mark: Int64, for chatId: String) { lock.withLock { marks[chatId] = mark } }
    func mark(of chatId: String) -> Int64 { lock.withLock { marks[chatId] ?? 0 } }
}
