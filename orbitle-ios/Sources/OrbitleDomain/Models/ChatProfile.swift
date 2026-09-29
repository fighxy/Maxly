import Foundation

/// Карточка чата для экрана профиля: собеседник, бот, группа или канал.
public struct ChatProfile: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case user, bot, group, channel
        /// Диалог с самим собой.
        case saved
    }

    /// Команда меню бота, без косой черты.
    public struct BotCommand: Hashable, Sendable {
        public let name: String
        public let description: String?

        public init(name: String, description: String? = nil) {
            self.name = name
            self.description = description
        }
    }

    public let kind: Kind
    public let chatId: String
    /// Собеседник или бот; у групп и каналов `nil`.
    public let peerId: String?
    public var title: String
    public var avatarURL: URL?
    public var description: String?
    /// Короткое имя (`helper_bot`) или полная ссылка, как прислал сервер.
    public var link: String?
    /// Номер в E.164 (`+79991234567`), если не скрыт.
    public var phone: String?
    /// Участники группы или подписчики канала.
    public var participants: Int?
    public var presence: Contact.Presence
    public var isOfficial: Bool
    public var isPublic: Bool
    public var commands: [BotCommand]

    public init(
        kind: Kind,
        chatId: String,
        peerId: String? = nil,
        title: String,
        avatarURL: URL? = nil,
        description: String? = nil,
        link: String? = nil,
        phone: String? = nil,
        participants: Int? = nil,
        presence: Contact.Presence = .unknown,
        isOfficial: Bool = false,
        isPublic: Bool = false,
        commands: [BotCommand] = []
    ) {
        self.kind = kind
        self.chatId = chatId
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
        self.description = description
        self.link = link
        self.phone = phone
        self.participants = participants
        self.presence = presence
        self.isOfficial = isOfficial
        self.isPublic = isPublic
        self.commands = commands
    }

    /// Публичная ссылка Max: полная как есть, короткое имя — `https://max.ru/<имя>`.
    public var linkURL: URL? {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty else { return nil }
        if link.hasPrefix("http://") || link.hasPrefix("https://") { return URL(string: link) }
        let name = link.hasPrefix("@") ? String(link.dropFirst()) : link
        return URL(string: "https://max.ru/" + name)
    }
}

/// Источник карточек чатов.
public protocol ChatProfileRepository: Sendable {
    func profile(chatId: String) async throws(OrbitleError) -> ChatProfile
}
