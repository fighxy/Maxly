import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Новый чат и контакт")
struct NewChatDataTests {
    private func person(_ id: String = "20") -> CoreContact {
        CoreContact(id: id, firstName: "Сервер", lastName: "Ли", phone: "79990000000", avatarURL: "", lastSeenMs: 0, online: false)
    }

    private func values<T: Sendable>(_ stream: AsyncStream<T>) async -> [T] {
        var all: [T] = []
        for await value in stream { all.append(value) }
        return all
    }

    @Test("Поиск по номеру не добавляет контакт, короткий номер не уходит")
    func findByPhone() async throws {
        let core = FakeMaxCore()
        await core.setPerson(phone: "+79990000000", person())
        let repository = CoreContactRepository(core: core)
        #expect(repository.capabilities.contains(.add))

        await #expect(throws: OrbitleError.invalidRequest) {
            try await repository.findByPhone("12-34")
        }
        #expect(await core.phoneQueries.isEmpty)

        let found = try await repository.findByPhone("8 (999) 000-00-00")
        #expect(found?.id == "20")
        #expect(await core.phoneQueries == ["+79990000000"])
        #expect(await core.contactAdds.isEmpty)
        #expect(await values(repository.contacts()) == [[]])

        await core.setPhoneFailure(CoreFailure(kind: "SERVER", key: "user.not.found"))
        #expect(try await repository.findByPhone("+79990000000") == nil)
        await core.setPhoneFailure(CoreFailure(kind: "NOT_FOUND", key: nil))
        #expect(try await repository.findByPhone("+79990000000") == nil)
        await core.setPhoneFailure(CoreFailure(kind: "NETWORK", key: nil))
        await #expect(throws: OrbitleError.networkUnavailable) {
            try await repository.findByPhone("+79990000000")
        }
    }

    @Test("Добавление ищет человека и шлёт только имя")
    func addSendsFirstNameOnly() async throws {
        let core = FakeMaxCore()
        await core.setPerson(phone: "+79990000000", person())
        let repository = CoreContactRepository(core: core)
        let saved = try await repository.addContact(phone: "+7 999 000-00-00", firstName: "Иван", lastName: "Петров")
        #expect(saved.id == "20")
        #expect(saved.firstName == "Иван")
        #expect(saved.lastName.isEmpty)
        #expect(await core.contactAdds == [("20", "Иван")])

        let blank = try await repository.addFoundContact(userId: "20", firstName: "  ")
        #expect(blank.firstName.isEmpty)
        #expect(await core.contactAdds.map(\.1) == ["Иван", ""])
        #expect(await values(repository.contacts()).last?.map(\.id) == ["20"])

        await core.setPhoneFailure(CoreFailure(kind: "MALFORMED_REPLY", key: nil))
        await #expect(throws: OrbitleError.rejected("Человек с таким номером не найден")) {
            try await repository.addContact(phone: "+79991111111", firstName: "А", lastName: "Б")
        }
    }

    @Test("Группа и канал из ответа попадают в список, пустой ответ — нет")
    func createdChats() async throws {
        let api = FakeMaxAPI()
        let stack = try SwiftDataStack(inMemory: true)
        let chats = ChatRepositoryImpl(modelContainer: stack.container, api: api)
        let when = Date(timeIntervalSince1970: 20)
        await api.setCreatedGroup(ChatRecord(id: "50", title: "Друзья", type: .group, updatedAt: when))
        #expect(try await chats.createGroup(title: "Друзья", memberIds: ["3"]) == "50")
        #expect(await api.groupCalls == [("Друзья", ["3"])])

        await api.setCreatedChannel(nil)
        #expect(try await chats.createChannel(title: "Пусто") == nil)

        await api.setCreatedChannel(ChatRecord(id: "60", title: "Новости", type: .channel, updatedAt: when))
        #expect(try await chats.createChannel(title: "Новости") == "60")
        await api.setJoinedChat(ChatRecord(id: "70", title: "По ссылке", type: .group, updatedAt: when))
        #expect(try await chats.joinByLink("https://max.ru/join/abc") == "70")

        var iterator = chats.chats().makeAsyncIterator()
        let rows = await iterator.next() ?? []
        #expect(rows.map(\.id).sorted() == ["50", "60", "70"])
        #expect(rows.first { $0.id == "60" }?.type == .channel)

        await api.setCreateError(.offline)
        await #expect(throws: OrbitleError.networkUnavailable) {
            try await chats.createGroup(title: "Сбой", memberIds: [])
        }
    }

    @Test("Клиент ядра передаёт создание канала и пустой ответ группы")
    func coreMapping() async throws {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        #expect(await client.createGroup(title: "Г", memberIds: []) == .success(nil))
        await core.setCreatedChat(CoreChat(
            id: "60", title: "Новости", type: "CHANNEL", lastMessageId: "", lastText: "", updatedAtMs: 1_000, unread: 0
        ))
        let created = await client.createChannel(title: "Новости")
        guard case .success(let record) = created else {
            Issue.record("канал не создан")
            return
        }
        #expect(record?.id == "60")
        #expect(record?.type == .channel)
        #expect(await core.channels == ["Новости"])
    }
}
