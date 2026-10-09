import Foundation

/// Участник группы в профиле.
public struct ProfileMember: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var avatarURL: URL?

    public init(id: String, name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// Чат, где есть и вы, и собеседник (`CHAT_SEARCH_COMMON_PARTICIPANTS` 198).
public struct CommonChat: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var isChannel: Bool
    public var avatarURL: URL?
    public var participants: Int

    public init(id: String, title: String, isChannel: Bool, avatarURL: URL? = nil, participants: Int = 0) {
        self.id = id
        self.title = title
        self.isChannel = isChannel
        self.avatarURL = avatarURL
        self.participants = participants
    }
}

/// Причина жалобы из списка сервера.
public struct ComplaintReason: Identifiable, Hashable, Sendable {
    public var id: Int
    public var title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

/// На кого жалоба: человек (тип `6`, id пользователя) или канал целиком (тип `2`, id чата).
public enum ComplaintTarget: Hashable, Sendable {
    case user(String)
    case channel(String)

    public var typeId: Int {
        switch self {
        case .user: 6
        case .channel: 2
        }
    }

    public var ids: [String] {
        switch self {
        case .user(let id), .channel(let id): [id]
        }
    }
}

/// Действия профиля, которых нет в самой карточке: участники, общие чаты, жалоба, блокировка.
public protocol ProfileActionsRepository: Sendable {
    func members(chatId: String) async throws(MaxlyError) -> [ProfileMember]
    func commonChats(userId: String) async throws(MaxlyError) -> [CommonChat]
    func complaintReasons(for target: ComplaintTarget) async throws(MaxlyError) -> [ComplaintReason]
    /// `true` — сервер принял жалобу.
    func complain(about target: ComplaintTarget, reasonId: Int) async throws(MaxlyError) -> Bool
    /// В чёрном списке ли пользователь. Список спрашивается один раз за сеанс.
    func isBlocked(userId: String) async throws(MaxlyError) -> Bool
    func setBlocked(userId: String, blocked: Bool) async throws(MaxlyError)
    /// Страница участников с ролями (`CHAT_MEMBERS` 59). Первая — с `ChatMembersRules.firstMarker`.
    func membersPage(chatId: String, marker: Int64) async throws(MaxlyError) -> ChatMembersPage
    /// Поиск участников на сервере по имени.
    func searchMembers(chatId: String, query: String) async throws(MaxlyError) -> [ChatMemberEntry]
    /// Совпадения среди загруженных: имя или имя для упоминаний, «@» — только оно.
    func filterMembers(_ members: [ChatMemberEntry], query: String) async -> [ChatMemberEntry]
}

public extension ProfileActionsRepository {
    /// Источник без страниц: весь список одной страницей, без ролей.
    func membersPage(chatId: String, marker: Int64) async throws(MaxlyError) -> ChatMembersPage {
        guard marker == ChatMembersRules.firstMarker else { return ChatMembersPage(members: [], marker: nil) }
        let rows = try await members(chatId: chatId)
        return ChatMembersPage(members: rows.map { ChatMemberEntry(id: $0.id, name: $0.name, avatarURL: $0.avatarURL) }, marker: nil)
    }

    /// Источник без поиска на сервере: экран ищет среди загруженных.
    func searchMembers(chatId: String, query: String) async throws(MaxlyError) -> [ChatMemberEntry] {
        throw .invalidRequest
    }

    func filterMembers(_ members: [ChatMemberEntry], query: String) async -> [ChatMemberEntry] {
        ChatMembersRules.filter(members, query: query)
    }
}
