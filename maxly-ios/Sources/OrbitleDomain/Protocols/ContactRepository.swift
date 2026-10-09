import Foundation

/// Что умеет источник контактов. Экран прячет или объясняет то, чего нет.
public struct ContactCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Список контактов аккаунта.
    public static let list = ContactCapabilities(rawValue: 1 << 0)
    /// Статус «в сети» и время последнего визита.
    public static let presence = ContactCapabilities(rawValue: 1 << 1)
    /// Добавление контакта по номеру.
    public static let add = ContactCapabilities(rawValue: 1 << 2)
    /// Переименование и удаление контакта (`CONTACT_UPDATE` 34, `UPDATE` и `REMOVE`).
    public static let edit = ContactCapabilities(rawValue: 1 << 3)
}

/// Имя контакта: имя обязательно, имя и фамилия — до 64 символов (как у сервера).
public enum ContactNameRules {
    public static let limit = 64

    /// Почему имя не подходит; `nil` — подходит. Пустое имя можно (как в веб-клиенте): с
    /// фамилией сервер покажет имя, которое человек указал сам, а без обоих вернутся его имена.
    public static func problem(firstName: String, lastName: String) -> String? {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.count > limit || last.count > limit { return "Не длиннее \(limit) символов" }
        return nil
    }
}

public protocol ContactRepository: Sendable {
    var capabilities: ContactCapabilities { get }
    /// Текущий список и все его изменения.
    func contacts() -> AsyncStream<[Contact]>
    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact
    /// Человек по номеру (`CONTACT_INFO_BY_PHONE` 46). `nil` — не найден. В контакты сам не попадает.
    /// Короче семи цифр запрос не уходит.
    func findByPhone(_ phone: String) async throws(OrbitleError) -> Contact?
    /// Уже известный пользователь в контакты (`CONTACT_UPDATE` 34, `action: ADD`). Пустое имя не уходит.
    func addFoundContact(userId: String, firstName: String) async throws(OrbitleError) -> Contact
    /// Попросить сервер прислать список заново. Новые подписки получат уже его.
    func sync() async throws(OrbitleError)
    /// Своё имя контакта (`CONTACT_UPDATE` 34, `UPDATE`); пустая фамилия не уходит.
    func rename(userId: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact
    /// Убрать из контактов (`CONTACT_UPDATE` 34, `REMOVE`). Чат с человеком остаётся.
    func remove(userId: String) async throws(OrbitleError)
}

public extension ContactRepository {
    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        throw .invalidRequest
    }

    func findByPhone(_ phone: String) async throws(OrbitleError) -> Contact? {
        throw .invalidRequest
    }

    func addFoundContact(userId: String, firstName: String) async throws(OrbitleError) -> Contact {
        throw .invalidRequest
    }

    func sync() async throws(OrbitleError) {}

    func rename(userId: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        throw .invalidRequest
    }

    func remove(userId: String) async throws(OrbitleError) {
        throw .invalidRequest
    }
}
