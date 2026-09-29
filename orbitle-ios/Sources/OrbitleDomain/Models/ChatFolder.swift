import Foundation

/// Папка списка чатов: серверная или локальный фильтр по типу.
public struct ChatFolder: Identifiable, Hashable, Sendable {
    /// Какие чаты попадают в папку.
    public enum Filter: Hashable, Sendable {
        /// Все чаты, кроме архива.
        case all
        case privateChats
        case groups
        case channels
        case bots
        case unread
        /// Серверная папка: перечисленные чаты.
        case chats(Set<String>)
        /// Серверная папка: перечисленные чаты и чаты под фильтры сервера.
        case rules(ChatFolderRules)
    }

    public let id: String
    public var title: String
    public var filter: Filter

    public init(id: String, title: String, filter: Filter) {
        self.id = id
        self.title = title
        self.filter = filter
    }

    public static let allId = "all"
    public static let all = ChatFolder(id: allId, title: "Все", filter: .all)

    /// Фильтры, которые клиент строит сам, когда у пользователя нет серверных папок.
    public static let localFilters: [ChatFolder] = [
        ChatFolder(id: "local.private", title: "Личные", filter: .privateChats),
        ChatFolder(id: "local.groups", title: "Группы", filter: .groups),
        ChatFolder(id: "local.channels", title: "Каналы", filter: .channels),
        ChatFolder(id: "local.bots", title: "Боты", filter: .bots),
        ChatFolder(id: "local.unread", title: "Непрочитанные", filter: .unread),
    ]

    /// Входит ли чат в папку. Архив в папки не попадает.
    public func contains(_ chat: Chat) -> Bool {
        guard !chat.isArchived else { return false }
        switch filter {
        case .all: return true
        case .privateChats: return chat.type == .private && !chat.isBot && !chat.isSavedMessages
        case .groups: return chat.type == .group
        case .channels: return chat.type == .channel
        case .bots: return chat.isBot
        case .unread: return chat.isUnread
        case .chats(let ids): return ids.contains(chat.id)
        case .rules(let rules): return rules.matches(chat)
        }
    }
}

/// Правила серверной папки: явный список чатов и фильтры.
///
/// Коды фильтров как у сервера MAX (сверено с Komet): 0 непрочитанные, 1 прочитанные,
/// 2 каналы, 3 группы, 4 диалоги, 5 владелец, 6 админ, 7 без звука, 8 контакты,
/// 9 не контакты, 10 боты, 11 со звуком, 12 отмеченные непрочитанными, 13 организации.
/// Сервер может прислать и имена (`CHANNEL`, `BOT`…). Типы объединяются по «или»,
/// состояния сужают по «и». Роли в чате, контакты и организации клиент не знает:
/// «контакты» и «не контакты» считаются диалогами, роли и организации не сужают.
public struct ChatFolderRules: Hashable, Sendable {
    public enum Code: Int, Sendable, CaseIterable {
        case unread = 0, read, channel, group, dialog, owner, admin, muted, contact, notContact, bot, notMuted, markedUnread, organization

        static let names: [String: Code] = [
            "UNREAD": .unread, "READ": .read, "CHANNEL": .channel, "CHAT": .group, "DIALOG": .dialog,
            "OWNER": .owner, "ADMIN": .admin, "MUTED": .muted, "CONTACT": .contact, "NOT_CONTACT": .notContact,
            "BOT": .bot, "NOT_MUTED": .notMuted, "MARKED_UNREAD": .markedUnread, "ORG": .organization,
        ]

        /// Код из текста сервера: число или имя. `nil` для незнакомого.
        public init?(text: String) {
            let value = text.trimmingCharacters(in: .whitespaces)
            if let number = Int(value), let code = Code(rawValue: number) {
                self = code
            } else if let code = Code.names[value.uppercased()] {
                self = code
            } else {
                return nil
            }
        }

        var isType: Bool { [.channel, .group, .dialog, .contact, .notContact, .bot, .organization].contains(self) }
    }

    public var chatIds: Set<String>
    public var codes: Set<Code>

    public init(chatIds: Set<String> = [], filters: [String] = []) {
        self.chatIds = chatIds
        self.codes = Set(filters.compactMap(Code.init(text:)))
    }

    public func matches(_ chat: Chat) -> Bool {
        if chatIds.contains(chat.id) { return true }
        let types = codes.filter(\.isType)
        let states = codes.filter { [.unread, .read, .muted, .notMuted, .markedUnread].contains($0) }
        guard !types.isEmpty || !states.isEmpty else { return false }
        if !types.isEmpty, !types.contains(where: { Self.isOfType(chat, $0) }) { return false }
        return states.allSatisfy { Self.isInState(chat, $0) }
    }

    private static func isOfType(_ chat: Chat, _ code: Code) -> Bool {
        switch code {
        case .channel: chat.type == .channel
        case .group: chat.type == .group
        case .dialog, .contact, .notContact: chat.type == .private && !chat.isBot && !chat.isSavedMessages
        case .bot: chat.isBot
        default: false
        }
    }

    private static func isInState(_ chat: Chat, _ code: Code) -> Bool {
        switch code {
        case .unread, .markedUnread: chat.isUnread
        case .read: !chat.isUnread
        case .muted: chat.isMuted
        case .notMuted: !chat.isMuted
        default: true
        }
    }
}
