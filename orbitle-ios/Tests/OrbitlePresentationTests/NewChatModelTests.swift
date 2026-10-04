import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private final class NewChatContacts: ContactRepository, @unchecked Sendable {
    let capabilities: ContactCapabilities = [.list, .presence, .add]
    private let lock = NSLock()
    private var list: [Contact]
    private(set) var lookups: [String] = []
    private(set) var adds: [(String, String)] = []
    var missing = false
    var failLookup = false
    var failAdd = false

    init(_ contacts: [Contact] = []) {
        list = contacts
    }

    func contacts() -> AsyncStream<[Contact]> {
        let snapshot = lock.withLock { list }
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    func findByPhone(_ phone: String) async throws(OrbitleError) -> Contact? {
        lock.withLock { lookups.append(phone) }
        if failLookup { throw .networkUnavailable }
        if missing { return nil }
        return Contact(id: "8", firstName: "Найденный", phone: phone)
    }

    func addFoundContact(userId: String, firstName: String) async throws(OrbitleError) -> Contact {
        if failAdd { throw .networkUnavailable }
        let contact = Contact(id: userId, firstName: firstName.isEmpty ? "Найденный" : firstName)
        lock.withLock {
            adds.append((userId, firstName))
            list.removeAll { $0.id == userId }
            list.append(contact)
        }
        return contact
    }
}

private final class NewChatChats: ChatRepository, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var prepared: [DialogDraft] = []
    private(set) var groups: [(String, [String])] = []
    private(set) var channels: [String] = []
    private(set) var links: [String] = []
    var groupId: String? = "50"
    var channelId: String? = "60"
    var linkId: String? = "70"
    var fail = false

    func chats() -> AsyncStream<[Chat]> {
        AsyncStream { $0.yield([]); $0.finish() }
    }

    func refresh() async throws(OrbitleError) {}
    func refresh(chatId: String) async throws(OrbitleError) {}
    func markAsRead(chatId: String) async throws(OrbitleError) {}

    func prepareDialog(_ draft: DialogDraft) async {
        lock.withLock { prepared.append(draft) }
    }

    func createGroup(title: String, memberIds: [String]) async throws(OrbitleError) -> String? {
        if fail { throw .networkUnavailable }
        lock.withLock { groups.append((title, memberIds)) }
        return groupId
    }

    func createChannel(title: String) async throws(OrbitleError) -> String? {
        if fail { throw .networkUnavailable }
        lock.withLock { channels.append(title) }
        return channelId
    }

    func joinByLink(_ link: String) async throws(OrbitleError) -> String? {
        if fail { throw .networkUnavailable }
        lock.withLock { links.append(link) }
        return linkId
    }
}

@Suite("Новое сообщение")
@MainActor
struct NewChatModelTests {
    func make(_ contacts: [Contact] = [Contact(id: "3", firstName: "Анна", phone: "+79990000003")]) -> (NewChatModel, NewChatContacts, NewChatChats) {
        let people = NewChatContacts(contacts)
        let chats = NewChatChats()
        let model = NewChatModel(contacts: people, chats: chats, currentUserId: "1")
        model.activate()
        return (model, people, chats)
    }

    @Test("Контакту пишут в диалог по исключающему или, без добавления в контакты")
    func writeToContact() async {
        let (model, people, chats) = make()
        _ = await eventually { model.people.map(\.id) == ["3"] }
        model.writeTo(personId: "3", title: "Анна")
        _ = await eventually { model.opened?.id == "2" }
        #expect(model.opened?.draft?.peerId == "3")
        #expect(chats.prepared.map(\.chatId) == ["2"])
        #expect(people.adds.isEmpty)
        model.writeTo(personId: "нет", title: "Анна")
        #expect(model.error == "Не удалось открыть чат")
    }

    @Test("Короткий номер не уходит, отсутствующий человек не открывает чат")
    func phoneLookup() async {
        let (model, people, _) = make()
        model.phone = "12345"
        model.lookup()
        #expect(model.error == "Номер слишком короткий")
        #expect(people.lookups.isEmpty)

        model.phone = "+7 999 000-00-00"
        people.missing = true
        model.lookup()
        _ = await eventually { model.error == "Человек с таким номером не найден" }
        #expect(people.lookups == ["+79990000000"])
        #expect(model.found == nil)
        #expect(model.opened == nil)

        people.failLookup = true
        people.missing = false
        model.lookup()
        _ = await eventually { model.error == "Не удалось найти человека" }
    }

    @Test("Написать найденному не добавляет его, добавление шлёт только имя")
    func writeFoundDoesNotAdd() async {
        let (model, people, chats) = make()
        model.phone = "79990000000"
        model.lookup()
        _ = await eventually { model.found?.id == "8" }
        model.contactName = "  Иван  "
        model.writeFound()
        _ = await eventually { model.opened?.id == "9" }
        #expect(people.adds.isEmpty)
        #expect(chats.prepared.count == 1)

        model.consumeOpened()
        model.addFound()
        _ = await eventually { model.notice == "Добавлен в контакты" }
        #expect(people.adds == [("8", "  Иван  ")])
        #expect(model.found?.added == true)
    }

    @Test("Пустое название не создаёт группу, участники уходят без себя")
    func groupAndChannel() async {
        let (model, _, chats) = make([
            Contact(id: "1", firstName: "Я"),
            Contact(id: "3", firstName: "Анна"),
            Contact(id: "4", firstName: "Борис"),
        ])
        _ = await eventually { model.people.map(\.id) == ["3", "4"] }
        model.createGroup()
        #expect(model.error == "Введите название")
        #expect(chats.groups.isEmpty)

        model.title = " Друзья "
        model.toggleMember("3")
        model.toggleMember("1")
        model.toggleMember("4")
        model.toggleMember("4")
        model.createGroup()
        _ = await eventually { model.opened?.id == "50" }
        #expect(chats.groups == [("Друзья", ["3"])])
        #expect(model.opened?.draft == nil)

        model.consumeOpened()
        chats.groupId = nil
        model.createGroup()
        _ = await eventually { model.error == "Не удалось создать группу" }

        model.title = "Новости"
        model.createChannel()
        _ = await eventually { model.opened?.id == "60" }
        #expect(chats.channels == ["Новости"])

        model.link = "   "
        model.joinLink()
        #expect(model.error == "Вставьте ссылку")
        model.link = "https://max.ru/join/abc"
        model.joinLink()
        _ = await eventually { model.opened?.id == "70" }
        #expect(chats.links == ["https://max.ru/join/abc"])
    }

    @Test("Номер собирается как плюс и цифры, название обрезается")
    func payload() {
        #expect(NewChatModel.phonePayload("123") == nil)
        #expect(NewChatModel.phonePayload("+7 (999) 000-00-00") == "+79990000000")
        let (model, _, _) = make()
        model.title = String(repeating: "я", count: 250)
        #expect(model.title.count == NewChatModel.titleLimit)
    }
}
