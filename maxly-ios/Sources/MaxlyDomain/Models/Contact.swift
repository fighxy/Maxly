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
    /// Опция `BOT`.
    public var isBot: Bool
    /// Опция `OFFICIAL`.
    public var isOfficial: Bool
    /// Опция `SERVICE_ACCOUNT`.
    public var isServiceAccount: Bool
    /// Имя, которое аккаунт сам дал контакту (`customName` ядра); пусто — своего имени нет
    /// и показывается имя, которое указал человек.
    public var customName: String

    public init(
        id: String,
        firstName: String,
        lastName: String = "",
        phone: String? = nil,
        avatarURL: URL? = nil,
        presence: Presence = .unknown,
        isBot: Bool = false,
        isOfficial: Bool = false,
        isServiceAccount: Bool = false,
        customName: String = ""
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.avatarURL = avatarURL
        self.presence = presence
        self.isBot = isBot
        self.isOfficial = isOfficial
        self.isServiceAccount = isServiceAccount
        self.customName = customName
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

public extension Contact.Presence {
    /// Код «статус не прислан» для `server(status:seenMs:)`.
    static let noStatus = -1

    /// Статус из полей протокола (`test-fixtures/presence`): `status` — `-1` не прислан,
    /// `0` не в сети, `1` в сети, `2` был недавно (время скрыто), `3` был давно, другой код —
    /// «недавно», как у веб-клиента Max; `seenMs` — время последнего визита в мс, `0` — нет.
    /// Без статуса и без времени — `.unknown`: показывать нечего.
    static func server(status: Int, seenMs: Int64) -> Contact.Presence {
        switch status {
        case 1: return .online
        case 3: return .longAgo
        case noStatus, 0:
            return seenMs > 0 ? .lastSeen(Date(timeIntervalSince1970: TimeInterval(seenMs) / 1000)) : .unknown
        default: return .recently
        }
    }
}

/// Своё имя контакта одной строкой (`customName` ядра) и обратно — имя и фамилия для полей.
public enum ContactCustomName {
    /// Первое слово — имя, остальное — фамилия. Пустая строка — оба поля пустые.
    public static func split(_ name: String) -> (firstName: String, lastName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(where: \.isWhitespace) else { return (trimmed, "") }
        let first = String(trimmed[..<space])
        let last = trimmed[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (first, last)
    }

    /// Имя и фамилия через пробел, без пустых частей.
    public static func join(firstName: String, lastName: String) -> String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Номер для сравнения с адресной книгой: последние десять цифр.
    public static func phoneKey(_ phone: String) -> String {
        String(phone.filter { $0.isASCII && $0.isNumber }.suffix(10))
    }
}
