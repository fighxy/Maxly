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
}

public protocol ContactRepository: Sendable {
    var capabilities: ContactCapabilities { get }
    /// Текущий список и все его изменения.
    func contacts() -> AsyncStream<[Contact]>
    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitlError) -> Contact
}

public extension ContactRepository {
    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitlError) -> Contact {
        throw .invalidRequest
    }
}
