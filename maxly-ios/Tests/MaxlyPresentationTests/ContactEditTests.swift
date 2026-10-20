import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Контакты, которые можно переименовать, удалить и вернуть.
private actor EditableContacts: ContactRepository {
    private(set) var list: [Contact]
    private(set) var log: [String] = []
    var failRemove = false
    var failAdd = false
    var failRename = false
    /// Как ядро при сбросе своего имени: ответ без имён, а в списке остаётся имя человека.
    var blankRenameReply = false
    /// Имя, которое человек указал сам: список показывает его после сброса своего имени.
    var ownNames: [String: (String, String)] = [:]

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
    func setFailAdd(_ value: Bool) { failAdd = value }
    func setFailRename(_ value: Bool) { failRename = value }
    func setBlankRenameReply(_ own: [String: (String, String)]) {
        blankRenameReply = true
        ownNames = own
    }

    func rename(userId: String, firstName: String, lastName: String) async throws(MaxlyError) -> Contact {
        log.append("rename \(userId) \(firstName) \(lastName)")
        if failRename { throw .networkUnavailable }
        guard let index = list.firstIndex(where: { $0.id == userId }) else { throw .invalidRequest }
        if blankRenameReply, firstName.isEmpty, lastName.isEmpty, let own = ownNames[userId] {
            list[index].firstName = own.0
            list[index].lastName = own.1
            list[index].customName = ""
            return Contact(id: userId, firstName: "", lastName: "")
        }
        list[index].firstName = firstName
        list[index].lastName = lastName
        return list[index]
    }

    func remove(userId: String) async throws(MaxlyError) {
        if failRemove { throw .networkUnavailable }
        log.append("remove \(userId)")
        list.removeAll { $0.id == userId }
    }

    func addFoundContact(userId: String, firstName: String) async throws(MaxlyError) -> Contact {
        if failAdd { throw .networkUnavailable }
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

    @Test("Пустое имя можно, но не длиннее 64 символов")
    func nameRules() {
        #expect(ContactNameRules.problem(firstName: "  ", lastName: "") == nil)
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
        // Пустое имя уходит как есть: сервер вернёт имена, которые человек указал сам.
        let empty = await model.rename(id: "5", firstName: "", lastName: "")
        #expect(empty)
        let tooLong = await model.rename(id: "5", firstName: String(repeating: "а", count: 65), lastName: "")
        #expect(!tooLong)
        #expect(model.errorMessage == "Не длиннее 64 символов")
        #expect(await repo.log == ["rename 5 Анна Петрова", "rename 5  "])
    }

    @Test("Отмена удаления возвращает своё имя контакта, а не показанное")
    func removeAndUndo() async {
        // Показано имя из адресной книги, своё имя в аккаунте — «Анна Петрова».
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня", lastName: "Работа", customName: "Анна Петрова")])
        let model = await ready(repo)
        await model.remove(id: "5")
        #expect(model.contact(id: "5") == nil)
        #expect(model.removed?.title == "Аня Работа")
        await model.undoRemove()
        #expect(model.removed == nil)
        #expect(model.errorMessage == nil)
        #expect(await repo.log == ["remove 5", "add 5 Анна", "rename 5 Анна Петрова"])
    }

    @Test("Без своего имени отмена просто возвращает контакт, без переименования")
    func undoWithoutCustomName() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня", lastName: "Петрова")])
        let model = await ready(repo)
        await model.remove(id: "5")
        await model.undoRemove()
        #expect(model.errorMessage == nil)
        #expect(await repo.log == ["remove 5", "add 5 Аня"])
    }

    @Test("Неудачная отмена показывает ошибку")
    func undoFailure() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня", lastName: "Петрова", customName: "Анна Петрова")])
        let model = await ready(repo)
        await model.remove(id: "5")
        await repo.setFailAdd(true)
        await model.undoRemove()
        #expect(model.errorMessage?.hasPrefix("Не удалось вернуть контакт") == true)

        // Контакт вернулся, а имя — нет: об этом тоже сказано, а не промолчано.
        let second = EditableContacts([Contact(id: "6", firstName: "Оля", lastName: "Ким", customName: "Ольга Ким")])
        let other = await ready(second)
        await other.remove(id: "6")
        await second.setFailRename(true)
        await other.undoRemove()
        #expect(other.errorMessage?.hasPrefix("Контакт вернулся, но не удалось вернуть его имя") == true)
    }

    @Test("Оба поля очищены, ответ без имени: видно имя, которое указал человек")
    func emptyRenameReply() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Зайка", lastName: "", customName: "Зайка")])
        await repo.setBlankRenameReply(["5": ("Анна", "Петрова")])
        let model = await ready(repo)
        let saved = await model.rename(id: "5", firstName: " ", lastName: "")
        #expect(saved)
        for _ in 0..<50 where model.contact(id: "5")?.displayName != "Анна Петрова" { await Task.yield() }
        #expect(model.contact(id: "5")?.displayName == "Анна Петрова")
    }

    @Test("Второе удаление не теряет первое: оно остаётся в силе, плашка заменяется")
    func secondRemoveReplacesBanner() async {
        let repo = EditableContacts([Contact(id: "5", firstName: "Аня"), Contact(id: "6", firstName: "Оля")])
        let model = await ready(repo)
        await model.remove(id: "5")
        await model.remove(id: "6")
        #expect(model.removed?.id == "6")
        #expect(model.isEditing == false)
        #expect(await repo.log == ["remove 5", "remove 6"])
    }

    @Test("Поля листа «Изменить контакт» — своё имя, без него пусто")
    func editFields() {
        let custom = ContactsViewModel.editFields(for: Contact(id: "5", firstName: "Аня", customName: "Анна Мария Петрова"))
        #expect(custom.firstName == "Анна")
        #expect(custom.lastName == "Мария Петрова")
        let none = ContactsViewModel.editFields(for: Contact(id: "5", firstName: "Аня"))
        #expect(none.firstName.isEmpty && none.lastName.isEmpty)
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
