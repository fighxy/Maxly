import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Кем прочитано и время правки: данные")
struct ReadersDataTests {
    private func repository(core: FakeMaxCore) throws -> MessageRepositoryImpl {
        let stack = try SwiftDataStack(inMemory: true)
        return MessageRepositoryImpl(modelContainer: stack.container, api: MaxAPIClient(core: core), latestReuse: 0)
    }

    private func record(_ id: String, author: String = "5", name: String = "", avatar: String = "", updateTimeMs: Int64 = 0) -> MessageRecord {
        MessageRecord(
            id: id, serverId: id, chatId: "-100", authorId: author, text: "Текст",
            timestamp: Date(timeIntervalSince1970: 100), status: .sent,
            authorName: name, authorAvatarURL: avatar, updateTimeMs: updateTimeMs
        )
    }

    @Test("Список ядра по серверному id, пустые имена и аватары — из сохранённых сообщений")
    func readersWithStoredNames() async throws {
        let core = FakeMaxCore()
        let repository = try repository(core: core)
        try await repository.upsert([
            record("10"),
            record("11", author: "7", name: "Анна", avatar: "https://cdn.example/anna.jpg"),
        ])
        await core.setReaders([
            MessageReader(userId: "7", reaction: "👍", readMark: nil),
            MessageReader(userId: "8", readMark: 100_000, name: "Борис"),
        ])
        let readers = try await repository.messageReaders(messageId: "10")
        #expect(await core.readerCalls == ["-100/10"])
        #expect(readers == [
            MessageReader(userId: "7", reaction: "👍", readMark: nil, name: "Анна", avatarURL: URL(string: "https://cdn.example/anna.jpg")),
            MessageReader(userId: "8", readMark: 100_000, name: "Борис"),
        ])
    }

    @Test("Неотправленное сообщение — пустой список без запроса, ошибка ядра — ошибка")
    func readersEdgeCases() async throws {
        let core = FakeMaxCore()
        let repository = try repository(core: core)
        #expect(try await repository.messageReaders(messageId: "local-1").isEmpty)
        #expect(await core.readerCalls.isEmpty)
        try await repository.upsert([record("10")])
        await core.setReaders([], error: CoreFailure(kind: "NETWORK", key: nil))
        await #expect(throws: OrbitleError.self) { _ = try await repository.messageReaders(messageId: "10") }
        // Ядро без «Кем прочитано» (фейк) — раздела нет.
        #expect(await repository.readersAvailable(chatId: "-100") == false)
    }

    @Test("updateTime: из сообщения ядра в ленту; запись без времени его не стирает")
    func editTime() async throws {
        let core = FakeMaxCore()
        let repository = try repository(core: core)
        let mapped = CoreMapping.message(CoreMessage(id: "10", chatId: "-100", authorId: "5", text: "Текст", timeMs: 100_000, updateTimeMs: 160_000))
        #expect(mapped.updateTimeMs == 160_000)
        try await repository.upsert([mapped])
        var stored = try await repository.page(chatId: "-100", before: nil, limit: 10)
        #expect(stored.first?.domain.editedAt == Date(timeIntervalSince1970: 160))

        try await repository.upsert([record("10")])
        stored = try await repository.page(chatId: "-100", before: nil, limit: 10)
        #expect(stored.first?.updateTimeMs == 160_000)

        #expect(try await repository.applyEdit(record("10", updateTimeMs: 200_000)))
        stored = try await repository.page(chatId: "-100", before: nil, limit: 10)
        #expect(stored.first?.domain.editedAt == Date(timeIntervalSince1970: 200))

        let plain = CoreMapping.message(CoreMessage(id: "11", chatId: "-100", authorId: "5", text: "Текст", timeMs: 100_000))
        #expect(plain.updateTimeMs == 0)
        #expect(plain.domain.editedAt == nil)
    }

    @Test("Пуш правки несёт updateTime")
    func editEvent() {
        let event = CoreEvent(kind: .edited, chatId: "-100", messageId: "10", authorId: "5", text: "Новый", title: "", chatType: "CHAT", timeMs: 100_000, unread: -1, updateTimeMs: 150_000)
        #expect(MessageRecord(event)?.updateTimeMs == 150_000)
    }
}
