import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private struct Card: ChatProfileRepository {
    let card: ChatProfile
    func profile(chatId: String) async throws(MaxlyError) -> ChatProfile { card }
}

private actor ProfileContacts: ContactRepository {
    private(set) var log: [String] = []
    nonisolated var capabilities: ContactCapabilities { [.list, .add, .edit] }
    nonisolated func contacts() -> AsyncStream<[Contact]> { AsyncStream { $0.finish() } }

    func rename(userId: String, firstName: String, lastName: String) async throws(MaxlyError) -> Contact {
        log.append("rename \(userId) \(firstName) \(lastName)")
        return Contact(id: userId, firstName: firstName, lastName: lastName)
    }

    func remove(userId: String) async throws(MaxlyError) {
        log.append("remove \(userId)")
    }

    func addFoundContact(userId: String, firstName: String) async throws(MaxlyError) -> Contact {
        log.append("add \(userId) \(firstName)")
        return Contact(id: userId, firstName: firstName)
    }
}

@MainActor
@Suite("Профиль: действия с контактом")
struct ChatProfileContactTests {
    private func model(_ card: ChatProfile, contacts: ProfileContacts = ProfileContacts(), me: String = "1") async -> ChatProfileViewModel {
        let model = ChatProfileViewModel(
            chatId: card.chatId, title: card.title, kind: card.kind,
            repository: Card(card: card), contacts: contacts, currentUserId: me
        )
        await model.load()
        return model
    }

    @Test("Контакт: «Изменить» и «Удалить из контактов»; поля — своё имя")
    func contactCanBeManaged() async {
        let card = ChatProfile(kind: .user, chatId: "7", peerId: "5", title: "Анна Петрова", isContact: true, customName: "Анна Петрова")
        let profile = await model(card)
        #expect(profile.contactAction == .manage)
        #expect(profile.contactEditFields.firstName == "Анна")
        #expect(profile.contactEditFields.lastName == "Петрова")
    }

    @Test("Без своего имени поля пустые, подсказка — имя человека")
    func emptyFieldsWithOwnNamePlaceholder() async {
        let card = ChatProfile(kind: .user, chatId: "7", peerId: "5", title: "Ivan Petrov", isContact: true)
        let profile = await model(card)
        #expect(profile.contactEditFields.firstName.isEmpty)
        #expect(profile.contactEditFields.lastName.isEmpty)
        #expect(profile.contactNamePlaceholder.firstName == "Ivan")
        #expect(profile.contactNamePlaceholder.lastName == "Petrov")
    }

    @Test("Не контакт: «Добавить в контакты»")
    func strangerCanBeAdded() async {
        let contacts = ProfileContacts()
        let card = ChatProfile(kind: .user, chatId: "7", peerId: "5", title: "Анна")
        let profile = await model(card, contacts: contacts)
        #expect(profile.contactAction == .add)
        #expect(await profile.addToContacts())
        #expect(await contacts.log == ["add 5 Анна"])
    }

    @Test("Свой профиль, «Избранное», бот, группа и канал — без действий с контактом")
    func noActionsForOthers() async {
        let me = ChatProfile(kind: .user, chatId: "0", peerId: "1", title: "Я", isContact: true)
        #expect(await model(me).contactAction == .none)
        let saved = ChatProfile(kind: .saved, chatId: "0", peerId: "1", title: "Избранное")
        #expect(await model(saved).contactAction == .none)
        let bot = ChatProfile(kind: .bot, chatId: "8", peerId: "9", title: "Бот", isContact: true)
        #expect(await model(bot).contactAction == .none)
        let group = ChatProfile(kind: .group, chatId: "-3", title: "Семья")
        #expect(await model(group).contactAction == .none)
        let channel = ChatProfile(kind: .channel, chatId: "-9", title: "Новости")
        #expect(await model(channel).contactAction == .none)
    }

    @Test("Переименование и удаление сообщают об изменении имён")
    func renameAndRemoveNotify() async {
        let contacts = ProfileContacts()
        let card = ChatProfile(kind: .user, chatId: "7", peerId: "5", title: "Анна", isContact: true)
        let profile = await model(card, contacts: contacts)
        var changes = 0
        profile.onNamesChanged = { changes += 1 }
        #expect(await profile.renameContact(firstName: " Аня ", lastName: "Работа"))
        #expect(profile.shown.customName == "Аня Работа")
        #expect(profile.title == "Аня Работа")
        #expect(await profile.removeContact())
        #expect(changes == 2)
        #expect(await contacts.log == ["rename 5 Аня Работа", "remove 5"])
    }
}
