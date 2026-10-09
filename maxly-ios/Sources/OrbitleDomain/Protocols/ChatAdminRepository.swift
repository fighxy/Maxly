import Foundation

/// Снимок группы или канала для экрана управления.
public struct ChatAdminSnapshot: Sendable, Equatable {
    public var title: String
    public var description: String
    public var link: String?
    public var ownerId: String?
    public var commentsEnabled: Bool?
    public var onlyOwnerRenames: Bool
    public var allCanPin: Bool
    public var onlyAdminAdds: Bool
    public var onlyAdminCalls: Bool
    public var membersSeeLink: Bool

    public init(title: String, description: String, link: String?, ownerId: String?, commentsEnabled: Bool?, onlyOwnerRenames: Bool, allCanPin: Bool, onlyAdminAdds: Bool, onlyAdminCalls: Bool, membersSeeLink: Bool) {
        self.title = title
        self.description = description
        self.link = link
        self.ownerId = ownerId
        self.commentsEnabled = commentsEnabled
        self.onlyOwnerRenames = onlyOwnerRenames
        self.allCanPin = allCanPin
        self.onlyAdminAdds = onlyAdminAdds
        self.onlyAdminCalls = onlyAdminCalls
        self.membersSeeLink = membersSeeLink
    }
}

public struct ChatAdminPerson: Identifiable, Hashable, Sendable {
    public enum Role: Hashable, Sendable { case owner, admin, member }
    public var id: String
    public var name: String
    public var role: Role
    public init(id: String, name: String, role: Role = .member) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public enum ChatGroupOption: Sendable {
    case onlyOwnerRenames, allCanPin, onlyAdminAdds, onlyAdminCalls, membersSeeLink
}

/// Управление группой и каналом. На iOS запись уходит в ядро, когда мост её отдаёт.
public protocol ChatAdminRepository: Sendable {
    func snapshot(chatId: String) async throws(OrbitleError) -> ChatAdminSnapshot
    func saveCard(chatId: String, title: String, description: String) async throws(OrbitleError)
    func setPhoto(chatId: String, jpeg: Data) async throws(OrbitleError)
    func members(chatId: String) async throws(OrbitleError) -> [ChatAdminPerson]
    func addMembers(chatId: String, userIds: [String]) async throws(OrbitleError)
    func removeMember(chatId: String, userId: String) async throws(OrbitleError)
    func setAdmin(chatId: String, userId: String, admin: Bool) async throws(OrbitleError)
    func revokeInviteLink(chatId: String) async throws(OrbitleError) -> String?
    func joinRequests(chatId: String) async throws(OrbitleError) -> [ChatAdminPerson]
    func decideJoinRequest(chatId: String, userId: String, accept: Bool) async throws(OrbitleError)
    func setOption(chatId: String, option: ChatGroupOption, enabled: Bool) async throws(OrbitleError)
    func setComments(chatId: String, enabled: Bool) async throws(OrbitleError)
    func blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String) async throws(OrbitleError)
}
