import Foundation

/// Контакт из адресной книги аккаунта.
public struct Contact: Identifiable, Hashable, Sendable {
    /// Когда человек был в сети. Сервер может скрыть точное время и прислать только
    /// примерный срок, как и принято в мессенджерах.
    public enum Presence: Hashable, Sendable, Codable {
        case online
        case lastSeen(Date)
        case recently
        case withinWeek
        case withinMonth
        case longAgo
        /// Сервер ничего не сообщил.
        case unknown
    }

    /// Id пользователя.
    public let id: String
    public var firstName: String
    public var lastName: String
    public var phone: String?
    public var avatarURL: URL?
    public var presence: Presence

    public init(
        id: String,
        firstName: String,
        lastName: String = "",
        phone: String? = nil,
        avatarURL: URL? = nil,
        presence: Presence = .unknown
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.avatarURL = avatarURL
        self.presence = presence
    }

    /// Имя для списка: имя и фамилия, иначе телефон.
    public var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        if let phone, !phone.isEmpty { return phone }
        return "Без имени"
    }
}
