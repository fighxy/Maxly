import Foundation
import OrbitleDomain

/// Ответ `MSG_DELETE` 66: удалённые и отклонённые сервером id.
public struct CoreDeleteResult: Sendable, Equatable {
    public var deleted: [String]
    public var failed: [String]

    public init(deleted: [String], failed: [String] = []) {
        self.deleted = deleted
        self.failed = failed
    }
}

/// Черновик сервера. `chatId` — чат ядра, `replyTo` пустой — без ответа.
public struct CoreDraft: Sendable, Equatable {
    public var chatId: String
    public var text: String
    public var elementsJSON: String
    public var replyTo: String
    /// Время черновика на сервере, мс.
    public var updateTime: Int64

    public init(chatId: String, text: String, elementsJSON: String = "[]", replyTo: String = "", updateTime: Int64) {
        self.chatId = chatId
        self.text = text
        self.elementsJSON = elementsJSON
        self.replyTo = replyTo
        self.updateTime = updateTime
    }
}

/// Контакт, добавленный по номеру, и новый ли он.
public struct CoreAddedContact: Sendable, Equatable {
    public var contact: CoreContact
    public var isNew: Bool

    public init(contact: CoreContact, isNew: Bool) {
        self.contact = contact
        self.isNew = isNew
    }
}

/// Запись адресной книги устройства. Номер как в книге: ядро приводит его само.
public struct CorePhoneContact: Sendable, Equatable {
    public var phone: String
    public var firstName: String
    public var lastName: String

    public init(phone: String, firstName: String, lastName: String = "") {
        self.phone = phone
        self.firstName = firstName
        self.lastName = lastName
    }
}

/// Участник группы или канала с ролью: `owner`, `admin` или `member`.
public struct CoreGroupMember: Sendable, Equatable {
    public var id: String
    public var name: String
    public var avatarURL: String
    public var role: String
    /// Подпись админа; пусто — «админ».
    public var alias: String
    public var lastSeenMs: Int64
    public var online: Bool
    /// Имя для упоминаний без «@»; пусто — нет.
    public var mentionName: String

    public init(id: String, name: String, avatarURL: String = "", role: String = "member", alias: String = "", lastSeenMs: Int64 = 0,
                online: Bool = false, mentionName: String = "") {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.role = role
        self.alias = alias
        self.lastSeenMs = lastSeenMs
        self.online = online
        self.mentionName = mentionName
    }
}

/// Свои права в чате (`chatRights`): владелец, админ, биты прав админа (`-1` — нет или
/// неизвестно) и право удалять любые сообщения.
public struct CoreChatRights: Sendable, Equatable {
    public var isOwner: Bool
    public var isAdmin: Bool
    public var permissions: Int64
    public var canDeleteAnyMessage: Bool

    public init(isOwner: Bool = false, isAdmin: Bool = false, permissions: Int64 = -1, canDeleteAnyMessage: Bool = false) {
        self.isOwner = isOwner
        self.isAdmin = isAdmin
        self.permissions = permissions
        self.canDeleteAnyMessage = canDeleteAnyMessage
    }
}

/// Диалог удаления выбранного (`deletePlan`): область на каждое сообщение (`all`, `self`,
/// `none`) и как показать переключатель «Удалить у всех».
public struct CoreDeletePlan: Sendable, Equatable {
    public var scopes: [String]
    public var canDelete: Bool
    public var showsForEveryone: Bool
    public var forEveryoneByDefault: Bool
    public var forcesForEveryone: Bool

    public init(scopes: [String], canDelete: Bool, showsForEveryone: Bool, forEveryoneByDefault: Bool, forcesForEveryone: Bool) {
        self.scopes = scopes
        self.canDelete = canDelete
        self.showsForEveryone = showsForEveryone
        self.forEveryoneByDefault = forEveryoneByDefault
        self.forcesForEveryone = forcesForEveryone
    }
}

/// Страница участников. Пустой `nextMarker` — страниц больше нет.
public struct CoreMembersPage: Sendable, Equatable {
    public var members: [CoreGroupMember]
    public var nextMarker: String

    public init(members: [CoreGroupMember], nextMarker: String) {
        self.members = members
        self.nextMarker = nextMarker
    }
}

/// Ядро без этих вызовов (фейки в тестах, источники без моста): правка и удаление идут
/// прежними вызовами, остальное — `unsupported`.
public extension MaxCore {
    func sendFormattedText(chatId: String, text: String, elementsJSON: String, replyTo: String) async throws -> CoreMessage {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func editMessage(chatId: String, messageId: String, text: String, elementsJSON: String) async throws -> CoreMessage {
        try await editMessage(chatId: chatId, messageId: messageId, text: text)
    }
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool, postId: String) async throws -> CoreDeleteResult {
        try await deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone)
        return CoreDeleteResult(deleted: messageIds)
    }
    func saveDraft(chatId: String, text: String, elementsJSON: String, replyTo: String) async throws -> Int64 {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func discardDraft(chatId: String, time: Int64) async throws {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func serverDrafts() async -> [CoreDraft] { [] }
    func renameContact(userId: String, firstName: String, lastName: String) async throws -> CoreContact {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func removeContact(userId: String) async throws -> CoreContact? {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func addContactByPhone(phone: String, firstName: String, lastName: String) async throws -> CoreAddedContact {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func setAddressBook(_ entries: [CorePhoneContact]) async {}

    func setPreferAddressBookNames(_ prefer: Bool) async {}
    func loadChatMembers(chatId: String, marker: String, count: Int) async throws -> CoreMembersPage {
        // Прежний вызов отдаёт только первую страницу без ролей.
        guard marker.isEmpty || marker == "0" else { return CoreMembersPage(members: [], nextMarker: "") }
        let members = try await chatMembers(chatId: chatId)
        return CoreMembersPage(
            members: members.map { CoreGroupMember(id: $0.id, name: $0.name, avatarURL: $0.avatarURL?.absoluteString ?? "") },
            nextMarker: ""
        )
    }
    func searchChatMembers(chatId: String, query: String) async throws -> [CoreGroupMember] {
        throw CoreFailure(kind: "UNKNOWN", key: "unsupported")
    }
    func filterMembers(_ members: [CoreGroupMember], query: String) async -> [CoreGroupMember]? { nil }

    /// Без ядра — то же общее правило (`drafts/merge.json`) по черновикам сервера и метке.
    func reconcileDraft(chatId: String, text: String, elementsJSON: String, replyTo: String, updateTime: Int64) async -> CoreDraft? {
        let server = await serverDrafts().first { $0.chatId == chatId }
        let mark = await draftDiscardedAt(chatId: chatId)
        let local = SyncedDraft(text: text, replyTo: replyTo.isEmpty ? nil : replyTo, updateTime: updateTime)
        let theirs = server.map { SyncedDraft(text: $0.text, replyTo: $0.replyTo.isEmpty ? nil : $0.replyTo, updateTime: $0.updateTime) }
        guard let winner = DraftSync.merge(local: local, server: theirs, discardedAt: mark > 0 ? mark : nil) else { return nil }
        if winner != local, let server { return server }
        return CoreDraft(chatId: chatId, text: winner.text, elementsJSON: elementsJSON, replyTo: winner.replyTo ?? "", updateTime: winner.updateTime)
    }
    func draftDiscardedAt(chatId: String) async -> Int64 { 0 }
    func chatRights(chatId: String) async -> CoreChatRights { CoreChatRights() }
    func editTimeoutSeconds() async -> Int64 { 0 }
    func deletePlan(chatId: String, messageIds: [String]) async -> CoreDeletePlan? { nil }
}
