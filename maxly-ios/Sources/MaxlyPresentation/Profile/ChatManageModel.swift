import Foundation
import Observation
import MaxlyDomain

@MainActor
@Observable
public final class ChatManageModel {
    public let isChannel: Bool
    public var title: String
    public var about: String
    public private(set) var link: String?
    public private(set) var members: [ChatAdminPerson] = []
    public private(set) var requests: [ChatAdminPerson] = []
    public private(set) var commentsEnabled: Bool?
    public private(set) var onlyOwnerRenames = false
    public private(set) var allCanPin = false
    public private(set) var onlyAdminAdds = false
    public private(set) var onlyAdminCalls = false
    public private(set) var membersSeeLink = false
    public private(set) var ownerId: String?
    public var message: String?
    public private(set) var busy = false

    private let chatId: String
    private let repository: any ChatAdminRepository

    public init(chatId: String, isChannel: Bool, title: String, about: String, repository: any ChatAdminRepository) {
        self.chatId = chatId
        self.isChannel = isChannel
        self.title = title
        self.about = about
        self.repository = repository
    }

    public func load() async {
        if let card = try? await repository.snapshot(chatId: chatId) { apply(card) }
        members = (try? await repository.members(chatId: chatId)) ?? members
        requests = (try? await repository.joinRequests(chatId: chatId)) ?? []
    }

    public func save() async { await run("Не удалось сохранить") { try await repository.saveCard(chatId: chatId, title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: about.trimmingCharacters(in: .whitespacesAndNewlines)); return "Сохранено" } }
    public func setPhoto(_ jpeg: Data) async { await run("Не удалось загрузить фото") { try await repository.setPhoto(chatId: chatId, jpeg: jpeg); return "Фото обновлено" } }
    public func revokeLink() async { await run("Не удалось обновить ссылку") { link = try await repository.revokeInviteLink(chatId: chatId); return "Ссылка обновлена" } }
    public func setComments(_ enabled: Bool) async { await run("Не удалось изменить комментарии") { try await repository.setComments(chatId: chatId, enabled: enabled); commentsEnabled = enabled; return enabled ? "Комментарии включены" : "Комментарии выключены" } }
    public func setOption(_ option: ChatGroupOption, _ enabled: Bool) async {
        await run("Не удалось изменить права") {
            try await repository.setOption(chatId: chatId, option: option, enabled: enabled)
            switch option {
            case .onlyOwnerRenames: onlyOwnerRenames = enabled
            case .allCanPin: allCanPin = enabled
            case .onlyAdminAdds: onlyAdminAdds = enabled
            case .onlyAdminCalls: onlyAdminCalls = enabled
            case .membersSeeLink: membersSeeLink = enabled
            }
            return "Права обновлены"
        }
    }
    public func add(_ userId: String) async { await run("Не удалось добавить") { try await repository.addMembers(chatId: chatId, userIds: [userId]); members = try await repository.members(chatId: chatId); return "Участник добавлен" } }
    public func remove(_ userId: String) async {
        guard userId != ownerId else { message = "Владельца удалить нельзя"; return }
        await run("Не удалось удалить") { try await repository.removeMember(chatId: chatId, userId: userId); members = try await repository.members(chatId: chatId); return "Участник удалён" }
    }
    public func setAdmin(_ userId: String, admin: Bool) async {
        guard userId != ownerId else { message = "Владелец уже управляет чатом"; return }
        await run("Не удалось изменить права") { try await repository.setAdmin(chatId: chatId, userId: userId, admin: admin); members = try await repository.members(chatId: chatId); return admin ? "Назначен админ" : "Админ снят" }
    }
    public func decide(_ userId: String, accept: Bool) async { await run("Не удалось разобрать заявку") { try await repository.decideJoinRequest(chatId: chatId, userId: userId, accept: accept); requests = try await repository.joinRequests(chatId: chatId); return accept ? "Заявка принята" : "Заявка отклонена" } }

    private func apply(_ card: ChatAdminSnapshot) {
        title = card.title
        about = card.description
        link = card.link
        ownerId = card.ownerId
        commentsEnabled = card.commentsEnabled
        onlyOwnerRenames = card.onlyOwnerRenames
        allCanPin = card.allCanPin
        onlyAdminAdds = card.onlyAdminAdds
        onlyAdminCalls = card.onlyAdminCalls
        membersSeeLink = card.membersSeeLink
    }

    private func run(_ fallback: String, _ body: () async throws -> String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            message = try await body()
        } catch {
            message = (error as? MaxlyError)?.userMessage ?? fallback
        }
    }
}
