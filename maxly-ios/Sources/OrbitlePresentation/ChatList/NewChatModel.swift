import Foundation
import Observation
import OrbitleDomain

/// Шаг листа «новое сообщение».
public enum NewChatStep: Equatable, Sendable {
    case menu
    case contact
    case phone
    case group
    case channel
    case link
}

/// Человек, найденный по номеру. В контакты сам не попадает.
public struct FoundPerson: Equatable, Sendable {
    public var id: String
    public var title: String
    public var phone: String
    public var added: Bool

    public init(id: String, title: String, phone: String, added: Bool = false) {
        self.id = id
        self.title = title
        self.phone = phone
        self.added = added
    }
}

/// Чат, который только что открыли или создали. Экран забирает его один раз.
public struct NewChatOpened: Equatable, Sendable {
    public var id: String
    public var title: String
    /// Личный диалог. У группы, канала и ссылки его нет: чат уже в списке.
    public var draft: DialogDraft?

    public init(id: String, title: String, draft: DialogDraft?) {
        self.id = id
        self.title = title
        self.draft = draft
    }
}

/// Написать контакту, найти человека по номеру, создать группу или канал, открыть ссылку.
/// Личный чат — исключающее «или» двух id: сервер создаёт диалог первым сообщением.
@MainActor
@Observable
public final class NewChatModel {
    public static let titleLimit = 200
    /// Короче этого запрос номера не уходит.
    public static let minPhoneDigits = 7

    public private(set) var step: NewChatStep = .menu
    public private(set) var people: [Contact] = []
    public private(set) var selected: [String] = []
    public private(set) var found: FoundPerson?
    public private(set) var busy = false
    public private(set) var error: String?
    public private(set) var notice: String?
    public private(set) var opened: NewChatOpened?

    public var query = ""
    public var phone = "" {
        didSet {
            guard phone != oldValue else { return }
            error = nil
            found = nil
            notice = nil
        }
    }
    public var title = "" {
        didSet { applyLimit(current: title, previous: oldValue) { title = $0 } }
    }
    public var contactName = "" {
        didSet { applyLimit(current: contactName, previous: oldValue) { contactName = $0 } }
    }
    public var link = "" {
        didSet { if link != oldValue { error = nil } }
    }

    public var stepTitle: String {
        switch step {
        case .menu: "Новое сообщение"
        case .contact: "Контакт"
        case .phone: "Новый человек"
        case .group: "Новая группа"
        case .channel: "Новый канал"
        case .link: "Ссылка"
        }
    }

    /// Контакты шага с учётом строки поиска.
    public var shownPeople: [Contact] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return people }
        let digits = term.filter(\.isNumber)
        return people.filter { person in
            person.displayName.localizedCaseInsensitiveContains(term)
                || (digits.count >= 3 && (person.phone ?? "").filter(\.isNumber).contains(digits))
        }
    }

    @ObservationIgnored private let contacts: any ContactRepository
    @ObservationIgnored private let chats: any ChatRepository
    @ObservationIgnored private let currentUserId: String
    @ObservationIgnored private var watch: Task<Void, Never>?
    /// Растёт, когда лист закрыли или начали другое действие: поздний ответ уже не открывает чат.
    @ObservationIgnored private var generation = 0

    public init(contacts: any ContactRepository, chats: any ChatRepository, currentUserId: String) {
        self.contacts = contacts
        self.chats = chats
        self.currentUserId = currentUserId
    }

    public func activate() {
        guard watch == nil else { return }
        let stream = contacts.contacts()
        watch = Task { [weak self] in
            for await list in stream {
                guard let self else { return }
                let me = self.currentUserId
                self.people = list
                    .filter { $0.id != me }
                    .sorted { ContactsViewModel.compare($0.displayName, $1.displayName) }
            }
        }
    }

    /// Снова с меню. Список контактов остаётся.
    public func show() {
        generation += 1
        step = .menu
        busy = false
        error = nil
        notice = nil
        opened = nil
        found = nil
        phone = ""
        title = ""
        contactName = ""
        link = ""
        query = ""
        selected = []
        // Поток контактов заканчивается после первого списка: при каждом открытии читаем его снова.
        reloadPeople()
    }

    public func dismiss() {
        show()
    }

    public func back() {
        generation += 1
        step = .menu
        busy = false
        error = nil
    }

    public func open(_ step: NewChatStep) {
        self.step = step
        error = nil
        notice = nil
    }

    public func toggleMember(_ id: String) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
    }

    public func consumeOpened() {
        opened = nil
        busy = false
    }

    /// Контакт из списка: чат открывается сразу, строка списка ставится локально.
    public func writeTo(personId: String, title: String) {
        guard !busy else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft = DialogDraft.with(peerId: personId, me: currentUserId, title: name.isEmpty ? "Чат" : name) else {
            error = "Не удалось открыть чат"
            return
        }
        let token = begin()
        Task {
            await chats.prepareDialog(draft)
            guard token == generation else { return }
            opened = NewChatOpened(id: draft.chatId, title: draft.title, draft: draft)
            busy = false
        }
    }

    public func lookup() {
        guard !busy else { return }
        guard let payload = Self.phonePayload(phone) else {
            error = "Номер слишком короткий"
            found = nil
            notice = nil
            return
        }
        let token = begin()
        found = nil
        notice = nil
        Task {
            do {
                let contact = try await contacts.findByPhone(payload)
                guard token == generation else { return }
                if let contact, !contact.id.isEmpty {
                    let number = contact.phone.flatMap { $0.isEmpty ? nil : $0 } ?? payload
                    found = FoundPerson(id: contact.id, title: contact.displayName, phone: number)
                } else {
                    error = "Человек с таким номером не найден"
                }
            } catch let failure as OrbitleError where failure == .cancelled {
                return
            } catch {
                guard token == generation else { return }
                self.error = "Не удалось найти человека"
            }
            if token == generation { busy = false }
        }
    }

    /// Написать найденному. В контакты это не добавляет.
    public func writeFound() {
        guard let person = found else { return }
        writeTo(personId: person.id, title: person.title)
    }

    /// Отдельное действие: записать найденного в контакты. Неудача не мешает написать.
    public func addFound() {
        guard let person = found, !person.added, !busy else { return }
        let token = begin()
        let name = contactName
        let id = person.id
        Task {
            do {
                _ = try await contacts.addFoundContact(userId: id, firstName: name)
                guard token == generation, found?.id == id else { return }
                found?.added = true
                notice = "Добавлен в контакты"
                reloadPeople()
            } catch let failure as OrbitleError where failure == .cancelled {
                return
            } catch {
                guard token == generation else { return }
                self.error = "Не удалось добавить в контакты"
            }
            if token == generation { busy = false }
        }
    }

    public func createGroup() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "Введите название"
            return
        }
        guard !busy else { return }
        let ids = selected.filter { $0 != currentUserId }
        launch(failure: "Не удалось создать группу", title: name) {
            try await self.chats.createGroup(title: name, memberIds: ids)
        }
    }

    public func createChannel() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "Введите название"
            return
        }
        guard !busy else { return }
        launch(failure: "Не удалось создать канал", title: name) {
            try await self.chats.createChannel(title: name)
        }
    }

    public func joinLink() {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            error = "Вставьте ссылку"
            return
        }
        guard !busy else { return }
        launch(failure: "Не удалось открыть ссылку", title: value) {
            try await self.chats.joinByLink(value)
        }
    }

    /// `+` и только цифры. Короче семи цифр — `nil`, запрос не уходит.
    public static func phonePayload(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= minPhoneDigits else { return nil }
        return "+\(digits)"
    }

    private func launch(failure: String, title: String, _ block: @escaping () async throws -> String?) {
        let token = begin()
        Task {
            do {
                let id = try await block()
                guard token == generation else { return }
                if let id, !id.isEmpty {
                    opened = NewChatOpened(id: id, title: title, draft: nil)
                } else {
                    error = failure
                }
            } catch let failureError as OrbitleError where failureError == .cancelled {
                return
            } catch {
                guard token == generation else { return }
                self.error = failure
            }
            if token == generation { busy = false }
        }
    }

    private func begin() -> Int {
        generation += 1
        busy = true
        error = nil
        return generation
    }

    private func reloadPeople() {
        watch?.cancel()
        watch = nil
        activate()
    }

    /// Обрезает поле до [titleLimit]. Повторная запись из `didSet` сюда уже не заходит.
    private func applyLimit(current: String, previous: String, write: (String) -> Void) {
        let capped = String(current.prefix(Self.titleLimit))
        if current != capped {
            write(capped)
            return
        }
        if current != previous { error = nil }
    }
}
