import Foundation
import OrbitleDomain

/// Действия профиля через ядро: участники группы, общие чаты, жалоба и чёрный список.
///
/// Чёрный список спрашивается один раз за сеанс (как в Komet) и дальше правится на месте:
/// своя блокировка или разблокировка меняет его сразу, без нового запроса.
public actor CoreProfileActions: ProfileActionsRepository {
    private let core: any MaxCore
    private var blocked: Set<String>?

    public init(core: any MaxCore) {
        self.core = core
    }

    public func members(chatId: String) async throws(OrbitleError) -> [ProfileMember] {
        try await run {
            try await core.chatMembers(chatId: chatId).map { ProfileMember(id: $0.id, name: $0.name, avatarURL: $0.avatarURL) }
        }
    }

    /// Пустой `nextMarker` ядра — страниц больше нет.
    public func membersPage(chatId: String, marker: Int64) async throws(OrbitleError) -> ChatMembersPage {
        try await run {
            // Роли — из карточки чата (owner, adminParticipants): перед первой страницей она
            // обновляется. Не вышло — список всё равно грузится, с ролями из прошлой карточки.
            if marker == ChatMembersRules.firstMarker {
                _ = try? await core.loadChat(id: chatId)
            }
            let page = try await core.loadChatMembers(chatId: chatId, marker: marker == 0 ? "" : String(marker), count: ChatMembersRules.pageSize)
            return ChatMembersPage(members: page.members.map(Self.entry), marker: Int64(page.nextMarker))
        }
    }

    public func searchMembers(chatId: String, query: String) async throws(OrbitleError) -> [ChatMemberEntry] {
        try await run { try await core.searchChatMembers(chatId: chatId, query: query).map(Self.entry) }
    }

    static func entry(_ member: CoreGroupMember) -> ChatMemberEntry {
        ChatMemberEntry(
            id: member.id,
            name: member.name,
            avatarURL: member.avatarURL.isEmpty ? nil : URL(string: member.avatarURL),
            role: ChatMemberRole(rawValue: member.role) ?? .member,
            alias: member.alias.isEmpty ? nil : member.alias
        )
    }

    public func commonChats(userId: String) async throws(OrbitleError) -> [CommonChat] {
        try await run { try await core.commonChats(userId: userId) }
    }

    public func complaintReasons(for target: ComplaintTarget) async throws(OrbitleError) -> [ComplaintReason] {
        try await run { try await core.complaintReasons(typeId: target.typeId) }
    }

    public func complain(about target: ComplaintTarget, reasonId: Int) async throws(OrbitleError) -> Bool {
        try await run { try await core.sendComplaint(reasonId: reasonId, typeId: target.typeId, ids: target.ids) }
    }

    public func isBlocked(userId: String) async throws(OrbitleError) -> Bool {
        if let blocked { return blocked.contains(userId) }
        let list = try await run { try await core.loadBlockedUsers() }
        let ids = Set(list.map(\.id))
        blocked = ids
        return ids.contains(userId)
    }

    public func setBlocked(userId: String, blocked flag: Bool) async throws(OrbitleError) {
        try await run {
            if flag { try await core.blockUser(userId) } else { try await core.unblockUser(userId) }
        }
        if flag { blocked?.insert(userId) } else { blocked?.remove(userId) }
    }

    /// Выход или смена аккаунта: чёрный список прежнего не должен пережить его.
    public func reset() {
        blocked = nil
    }

    private func run<T: Sendable>(_ body: () async throws -> T) async throws(OrbitleError) -> T {
        do {
            return try await body()
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }
}
