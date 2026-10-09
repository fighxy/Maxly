import Foundation
import Observation
import MaxlyDomain

/// Строка списка контактов.
public struct ContactRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let isOnline: Bool
    public let avatarURL: URL?
    public let isOfficial: Bool

    public init(id: String, title: String, status: String, isOnline: Bool, avatarURL: URL?, isOfficial: Bool = false) {
        self.id = id
        self.title = title
        self.status = status
        self.isOnline = isOnline
        self.avatarURL = avatarURL
        self.isOfficial = isOfficial
    }
}

/// Раздел списка на одну букву. Пустые разделы есть только ради полного алфавитного
/// указателя: по нажатию на букву без контактов список встаёт на её место.
public struct ContactSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let rows: [ContactRow]

    public init(id: String, rows: [ContactRow]) {
        self.id = id
        self.rows = rows
    }

    public var title: String { id }
}

/// Вкладка «Контакты»: разделы по буквам, поиск и статус «в сети».
@MainActor
@Observable
public final class ContactsViewModel {
    public enum State: Equatable, Sendable {
        case loading
        /// Источник не умеет отдавать контакты.
        case unavailable
        case empty
        case ready
    }

    /// Буквы указателя: кириллица, латиница, затем «#» для остального.
    public static let cyrillicIndex = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЭЮЯ".map(String.init)
    public static let latinIndex = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
    public static let otherIndex = "#"
    public static let indexTitles = cyrillicIndex + latinIndex + [otherIndex]

    public private(set) var state: State = .loading
    /// Разделы для полного указателя, включая пустые. Во время поиска пусто.
    public private(set) var sections: [ContactSection] = []
    /// Найденные контакты одним списком.
    public private(set) var searchResults: [ContactRow] = []
    public private(set) var errorMessage: String?

    public var query = "" {
        didSet { if query != oldValue { rebuild() } }
    }

    public var isSearching = false {
        didSet { if !isSearching, !query.isEmpty { query = "" } }
    }

    public var isFiltering: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var canAdd: Bool { repository.capabilities.contains(.add) }
    /// Сколько контактов всего.
    public var count: Int { contacts.count }

    @ObservationIgnored private let repository: any ContactRepository
    @ObservationIgnored private let currentUserId: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let formatter: ContactsFormatter
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var presenceWatch: Task<Void, Never>?
    @ObservationIgnored private var contacts: [Contact] = []
    /// Живые статусы «в сети»; `nil` — статусы только из списка контактов.
    @ObservationIgnored private let presence: (any PresenceProvider)?
    /// Статусы, пришедшие после списка (`loadPresence`, события ядра), по id.
    @ObservationIgnored private var live: [String: Contact.Presence] = [:]

    public init(
        contacts: any ContactRepository,
        currentUserId: String,
        formatter: ContactsFormatter = ContactsFormatter(),
        presence: (any PresenceProvider)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = contacts
        self.currentUserId = currentUserId
        self.formatter = formatter
        self.presence = presence
        self.now = now
    }

    public func activate() {
        guard watch == nil else { return }
        guard repository.capabilities.contains(.list) else {
            state = .unavailable
            return
        }
        let stream = repository.contacts()
        watch = Task { [weak self] in
            for await list in stream {
                guard let self else { return }
                self.contacts = list.filter { $0.id != self.currentUserId }
                self.rebuild()
                self.requestPresence()
            }
        }
        if let presence {
            let changes = presence.changes()
            presenceWatch = Task { [weak self] in
                for await ids in changes {
                    guard let self else { return }
                    await self.applyPresence(ids, from: presence)
                }
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
        presenceWatch?.cancel()
        presenceWatch = nil
    }

    /// Спросить статусы контактов, не задерживая показ списка.
    private func requestPresence() {
        guard let presence, !contacts.isEmpty else { return }
        let ids = contacts.map(\.id)
        Task { [weak self] in
            await presence.refresh(ids)
            // Уже известные статусы не приходят как изменения: читаем их сами.
            await self?.applyPresence(Set(ids), from: presence)
        }
    }

    /// Статусы изменились: строки этих контактов пересчитываются.
    func applyPresence(_ ids: Set<String>, from presence: any PresenceProvider) async {
        let known = Set(contacts.map(\.id))
        var changed = false
        for id in ids where known.contains(id) {
            guard let value = await presence.presence(of: id), live[id] != value else { continue }
            live[id] = value
            changed = true
        }
        if changed { rebuild() }
    }

    /// Пересчитать «был(а) 5 минут назад» и подобное: экран зовёт раз в минуту,
    /// иначе относительное время застывало на момент загрузки списка.
    public func refreshTimes() {
        guard !contacts.isEmpty else { return }
        rebuild()
    }

    /// Синхронизировать контакты с сервером и перечитать список.
    /// Неудача синхронизации не мешает: показывается прежний список.
    public func sync() async {
        try? await repository.sync()
        deactivate()
        activate()
    }

    /// Раздел, к которому прокрутить по букве указателя: сама буква, если в ней есть
    /// контакты, иначе ближайшая следующая, иначе последняя непустая.
    public func sectionId(forIndexTitle title: String) -> String? {
        let filled = sections.filter { !$0.rows.isEmpty }.map(\.id)
        guard !filled.isEmpty else { return nil }
        if filled.contains(title) { return title }
        let order = Self.indexTitles
        guard let position = order.firstIndex(of: title) else { return filled.last }
        return order[position...].first { filled.contains($0) } ?? filled.last
    }

    /// Диалог с контактом. Id личного чата в Max — исключающее «или» двух id пользователей.
    public func chatId(forContact id: String) -> String? {
        guard let me = Int64(currentUserId), let other = Int64(id) else { return nil }
        return String(me ^ other)
    }

    /// Диалог с контактом: имя и аватар для экрана чата, пока диалога нет в списке.
    public func dialog(forContact id: String) -> DialogDraft? {
        guard let contact = contacts.first(where: { $0.id == id }) else { return nil }
        return DialogDraft.with(peerId: id, me: currentUserId, title: contact.displayName, avatarURL: contact.avatarURL)
    }

    public func addContact(phone: String, firstName: String, lastName: String) async -> Bool {
        do {
            _ = try await repository.addContact(phone: phone, firstName: firstName, lastName: lastName)
            errorMessage = nil
            // Поток списка уже закончился: переподписка показывает человека, которого только что записали.
            deactivate()
            activate()
            return true
        } catch {
            errorMessage = error.userMessage
            return false
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: Переименование и удаление

    /// Удалённый контакт, пока висит плашка «Отменить».
    public struct RemovedContact: Identifiable, Equatable, Sendable {
        public let id: String
        public let firstName: String
        public let lastName: String
        public var title: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    public var canEdit: Bool { repository.capabilities.contains(.edit) }
    /// Последний удалённый: плашка с «Отменить», пока её не закрыли.
    public private(set) var removed: RemovedContact?
    /// Идёт запрос переименования, удаления или возврата.
    public private(set) var isEditing = false

    public func contact(id: String) -> Contact? {
        contacts.first { $0.id == id }
    }

    /// `true` — сервер принял новое имя, список уже с ним.
    public func rename(id: String, firstName: String, lastName: String) async -> Bool {
        if let problem = ContactNameRules.problem(firstName: firstName, lastName: lastName) {
            errorMessage = problem
            return false
        }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = true
        defer { isEditing = false }
        do {
            let saved = try await repository.rename(userId: id, firstName: first, lastName: last)
            if let index = contacts.firstIndex(where: { $0.id == id }) {
                var updated = contacts[index]
                // Ответ без имени — сервер вернул прежние имена или их ещё нет в ответе.
                let answered = !saved.firstName.isEmpty || !saved.lastName.isEmpty
                updated.firstName = answered ? saved.firstName : first
                updated.lastName = answered ? saved.lastName : last
                contacts[index] = updated
                rebuild()
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.userMessage
            return false
        }
    }

    /// Убрать из контактов. Строка уходит сразу, плашка предлагает «Отменить».
    public func remove(id: String) async {
        guard let contact = contact(id: id) else { return }
        isEditing = true
        defer { isEditing = false }
        do {
            try await repository.remove(userId: id)
            contacts.removeAll { $0.id == id }
            removed = RemovedContact(id: id, firstName: contact.firstName, lastName: contact.lastName)
            errorMessage = nil
            rebuild()
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// «Отменить»: контакт возвращается с прежним именем.
    public func undoRemove() async {
        guard let removed else { return }
        self.removed = nil
        isEditing = true
        defer { isEditing = false }
        do {
            _ = try await repository.addFoundContact(userId: removed.id, firstName: removed.firstName)
            if !removed.lastName.isEmpty {
                _ = try? await repository.rename(userId: removed.id, firstName: removed.firstName, lastName: removed.lastName)
            }
            errorMessage = nil
            deactivate()
            activate()
        } catch {
            errorMessage = error.userMessage
        }
    }

    public func dismissRemoved() {
        removed = nil
    }

    // MARK: Внутреннее

    private func rebuild() {
        guard repository.capabilities.contains(.list) else { return }
        let date = now()
        let sorted = contacts.sorted { Self.compare($0.displayName, $1.displayName) }
        if isFiltering {
            searchResults = ContactsViewModel.search(sorted, query: query).map { row(for: $0, now: date) }
        } else {
            searchResults = []
        }
        guard !sorted.isEmpty else {
            sections = []
            state = .empty
            return
        }
        let grouped = Dictionary(grouping: sorted) { Self.indexTitle(for: $0.displayName) }
        sections = Self.indexTitles.map { letter in
            ContactSection(id: letter, rows: (grouped[letter] ?? []).map { row(for: $0, now: date) })
        }
        state = .ready
    }

    private func row(for contact: Contact, now: Date) -> ContactRow {
        let presence = live[contact.id] ?? contact.presence
        let seen = formatter.status(presence, now: now)
        let status: String
        if presence == .online {
            status = seen
        } else if contact.isServiceAccount {
            status = "Служебный аккаунт"
        } else if contact.isBot {
            status = "Бот"
        } else {
            status = seen
        }
        return ContactRow(
            id: contact.id,
            title: contact.displayName,
            status: status,
            isOnline: presence == .online,
            avatarURL: contact.avatarURL,
            isOfficial: contact.isOfficial
        )
    }

    /// Буква указателя для имени: первая буква, «Ё» вместе с «Е», остальное — «#».
    public static func indexTitle(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return otherIndex }
        var letter = String(first).uppercased()
        if letter == "Ё" { letter = "Е" }
        if cyrillicIndex.contains(letter) || latinIndex.contains(letter) { return letter }
        // Латиница с диакритикой: «É» → «E».
        let plain = letter.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        if latinIndex.contains(plain) { return plain }
        return otherIndex
    }

    /// Кириллица раньше латиницы, остальное в конце; внутри — по алфавиту без учёта регистра.
    static func compare(_ lhs: String, _ rhs: String) -> Bool {
        let left = rank(lhs)
        let right = rank(rhs)
        if left != right { return left < right }
        let a = ChatListSearch.normalize(lhs)
        let b = ChatListSearch.normalize(rhs)
        if a != b { return a < b }
        return lhs < rhs
    }

    private static func rank(_ name: String) -> Int {
        let letter = indexTitle(for: name)
        if cyrillicIndex.contains(letter) { return 0 }
        if latinIndex.contains(letter) { return 1 }
        return 2
    }

    /// Поиск по имени (с начала слова или внутри) и по цифрам телефона.
    static func search(_ contacts: [Contact], query: String) -> [Contact] {
        let needle = ChatListSearch.normalize(query)
        guard !needle.isEmpty else { return contacts }
        let digits = query.filter(\.isASCIIDigit)
        let ranked = contacts.compactMap { contact -> (Contact, Int)? in
            if let rank = ChatListSearch.rank(title: contact.displayName, query: query) {
                return (contact, rank)
            }
            if digits.count >= 3, let phone = contact.phone, phone.filter(\.isASCIIDigit).contains(digits) {
                return (contact, 3)
            }
            return nil
        }
        return ranked.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
    }
}

/// Тексты статуса контакта.
public struct ContactsFormatter: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = ChatListFormatter.defaultCalendar()) {
        self.calendar = calendar
    }

    /// Пустая строка — статус неизвестен (ядро ничего не прислало): строку статуса не показывать.
    /// Раньше неизвестное выглядело как «Был(а) недавно», и после запуска так были почти все.
    public func status(_ presence: Contact.Presence, now: Date) -> String {
        switch presence {
        case .online:
            return "В сети"
        case .unknown:
            return ""
        case .recently:
            return "Был(а) недавно"
        case .withinWeek:
            return "Был(а) на этой неделе"
        case .withinMonth:
            return "Был(а) в этом месяце"
        case .longAgo:
            return "Был(а) давно"
        case .lastSeen(let date):
            return lastSeen(date, now: now)
        }
    }

    private func lastSeen(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        // Время из будущего (часы устройства отстают) — тоже «только что», а не дата.
        if seconds < 60 { return "Был(а) только что" }
        if seconds > 0, seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "Был(а) \(minutes) \(Self.minutesWord(minutes)) назад"
        }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0:
            return "Был(а) в \(time)"
        case 1:
            return "Был(а) вчера в \(time)"
        default:
            let day = parts.day ?? 1
            let month = ChatListFormatter.months[((parts.month ?? 1) - 1) % 12]
            if days > 0, parts.year == calendar.component(.year, from: now) {
                return "Был(а) \(day) \(month)"
            }
            return String(format: "Был(а) %02d.%02d.%04d", day, parts.month ?? 1, parts.year ?? 0)
        }
    }

    /// «1 минуту», «2 минуты», «5 минут».
    static func minutesWord(_ count: Int) -> String {
        let tens = count % 100
        let units = count % 10
        if (11...14).contains(tens) { return "минут" }
        switch units {
        case 1: return "минуту"
        case 2...4: return "минуты"
        default: return "минут"
        }
    }
}
