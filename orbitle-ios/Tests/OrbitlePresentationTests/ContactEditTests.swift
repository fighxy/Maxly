import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Контакты, которые можно переименовать, удалить и вернуть.
private actor EditableContacts: ContactRepository {
    private(set) var list: [Contact]
    private(set) var log: [String] = []
    var failRemove = false

    init(_ list: [Contact]) { self.list = list }

    nonisolated var capabilities: ContactCapabilities { [.list, .add, .edit] }

    nonisolated func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await self.list)
                continuation.finish()
            }
        }
    }

    func setFailRemove(_ value: Bool) { failRemove = value }

    func rename(userId: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        log.append("rename \(userId) \(firstName) \(lastName)")
        guard let index = list.firstIndex(where: { $0.id == userId }) else { throw .invalidRequest }
        list[index].firstName = firstName
        list[index].lastName = lastName
        return list[index]
    }

    func remove(userId: String) async throws(OrbitleError) {
        if failRemove { throw .networkUnavailable }
        log.append("remove \(userId)")
        list.removeAll { $0.id == userId }
    }

    func addFoundContact(userId: String, firstName: String) async throws(OrbitleError) -> Contact {
        log.append("add \(userId) \(firstName)")
        let contact = Contact(id: userId, firstName: firstName, lastName: "")
        list.append(contact)
        return contact
    }
}

@MainActor
@Suite("Контакты: переименование и удаление")
struct ContactEditTests {
    private func ready(_ repo: EditableContacts) async -> ContactsViewModel {
        let model = ContactsViewModel(contacts: repo, currentUserId: "1")
        model.activate()
        for _ in 0..<50 where model.count == 0 { await Task.yield() }
        return model
    }

    @Test("Имя обязательно и не длиннее 64 символов")
    func nameRules() {
        #expect(ContactNameRules.problem(firstName: "  ", lastName: "") == "Введите имя")
        #expect(ContactNameRules.problem(firstName: String(repeating: "а", count: 65), lastName: "") == "Не длиннее 64 символов")
        #expect(ContactNameRules.problem(firstName: "Аня", lastName: String(repeating: "б", count: 65)) == "Не длиннее 64 символов")
        #expect(ContactNameRules.problem(firstName: String(repeating: "а", count: 64), lastName: "") == nil)
    }

    @Test("Переименование уходит на сервер и сразу видно в списке")
    func rename() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня", lastName: "")])
        let model = await ready(repo)
        let saved = await model.rename(id: "5", firstName: " Анна ", lastName: "Петрова")
        #expect(saved)
        #expect(model.contact(id: "5")?.displayName == "Анна Петрова")
        let empty = await model.rename(id: "5", firstName: "", lastName: "")
        #expect(!empty)
        #expect(model.errorMessage == "Введите имя")
        #expect(await repo.log == ["rename 5 Анна Петрова"])
    }

    @Test("Удаление убирает строку и предлагает «Отменить», отмена возвращает контакт")
    func removeAndUndo() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня", lastName: "Петрова")])
        let model = await ready(repo)
        await model.remove(id: "5")
        #expect(model.contact(id: "5") == nil)
        #expect(model.removed?.title == "Аня Петрова")
        await model.undoRemove()
        #expect(model.removed == nil)
        #expect(await repo.log == ["remove 5", "add 5 Аня", "rename 5 Аня Петрова"])
    }

    @Test("Сервер не удалил — строка остаётся, плашки нет")
    func removeFailure() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня", lastName: "")])
        await repo.setFailRemove(true)
        let model = await ready(repo)
        await model.remove(id: "5")
        #expect(model.contact(id: "5") != nil)
        #expect(model.removed == nil)
        #expect(model.errorMessage != nil)
    }
}
