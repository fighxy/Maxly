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
        }
    }
}
