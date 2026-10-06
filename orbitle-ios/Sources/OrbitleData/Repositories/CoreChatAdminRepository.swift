import Foundation
import OrbitleDomain

/// Управление чатом через мост ядра. Пока собранный `MaxIos` не содержит эти методы,
/// запись отвечает отказом, а список участников берётся из уже существующего `chatMembers`.
public struct CoreChatAdminRepository: ChatAdminRepository, Sendable {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func snapshot(chatId: String) async throws(OrbitleError) -> ChatAdminSnapshot {
        try await core.chatAdminSnapshot(chatId: chatId)
    }

    public func saveCard(chatId: String, title: String, description: String) async throws(OrbitleError) {
        try await core.saveChatCard(chatId: chatId, title: title, description: description)
    }

    public func setPhoto(chatId: String, jpeg: Data) async throws(OrbitleError) {
        try await core.setChatPhoto(chatId: chatId, jpeg: jpeg)
    }

    public func members(chatId: String) async throws(OrbitleError) -> [ChatAdminPerson] {
        do {
            return try await core.chatMembers(chatId: chatId).map {
                ChatAdminPerson(id: $0.id, name: $0.name.isEmpty ? "Участник" : $0.name)
            }
        } catch {
            throw (error as? OrbitleError) ?? .unknown
        }
    }

    public func addMembers(chatId: String, userIds: [String]) async throws(OrbitleError) {
        try await core.addChatMembers(chatId: chatId, userIds: userIds)
    }

    public func removeMember(chatId: String, userId: String) async throws(OrbitleError) {
        try await core.removeChatMember(chatId: chatId, userId: userId)
    }

    public func setAdmin(chatId: String, userId: String, admin: Bool) async throws(OrbitleError) {
        try await core.setChatAdmin(chatId: chatId, userId: userId, admin: admin)
    }

    public func revokeInviteLink(chatId: String) async throws(OrbitleError) -> String? {
        try await core.revokeChatInviteLink(chatId: chatId)
    }

    public func joinRequests(chatId: String) async throws(OrbitleError) -> [ChatAdminPerson] {
        try await core.chatJoinRequests(chatId: chatId)
    }

    public func decideJoinRequest(chatId: String, userId: String, accept: Bool) async throws(OrbitleError) {
        try await core.decideChatJoinRequest(chatId: chatId, userId: userId, accept: accept)
    }

    public func setOption(chatId: String, option: ChatGroupOption, enabled: Bool) async throws(OrbitleError) {
        try await core.setChatOption(chatId: chatId, option: option, enabled: enabled)
    }

    public func setComments(chatId: String, enabled: Bool) async throws(OrbitleError) {
        try await core.setChannelComments(chatId: chatId, enabled: enabled)
    }

    public func blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String) async throws(OrbitleError) {
        try await core.blockCommentAuthor(chatId: chatId, postId: postId, userId: userId, messageId: messageId)
    }
}

/// Методы моста, которых ещё нет в опубликованном `MaxIos`. Реализация по умолчанию — отказ.
/// Когда ядро начнёт их отдавать, `MaxIosCore` перекроет эти методы.
public extension MaxCore {
    func chatAdminSnapshot(chatId: String) async throws(OrbitleError) -> ChatAdminSnapshot { throw .rejected(chatAdminBridgeMissing) }
    func saveChatCard(chatId: String, title: String, description: String) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func setChatPhoto(chatId: String, jpeg: Data) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func addChatMembers(chatId: String, userIds: [String]) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func removeChatMember(chatId: String, userId: String) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func setChatAdmin(chatId: String, userId: String, admin: Bool) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func revokeChatInviteLink(chatId: String) async throws(OrbitleError) -> String? { throw .rejected(chatAdminBridgeMissing) }
    func chatJoinRequests(chatId: String) async throws(OrbitleError) -> [ChatAdminPerson] { throw .rejected(chatAdminBridgeMissing) }
    func decideChatJoinRequest(chatId: String, userId: String, accept: Bool) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func setChatOption(chatId: String, option: ChatGroupOption, enabled: Bool) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func setChannelComments(chatId: String, enabled: Bool) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
    func blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String) async throws(OrbitleError) { throw .rejected(chatAdminBridgeMissing) }
}

private let chatAdminBridgeMissing = "Управление чатом на iOS ждёт следующую сборку ядра"
