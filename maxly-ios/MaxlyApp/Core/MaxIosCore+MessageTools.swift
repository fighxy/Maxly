import Foundation
import MaxlyData
import MaxlyDomain
import MaxlyCore

/// Разметка, удаление выбранного, черновики сервера, участники с ролями, правка контактов
/// и адресная книга. Числа в колбэках Kotlin приходят упакованными.
extension MaxIosCore {
    func sendFormattedText(chatId: String, text: String, elementsJSON: String, replyTo: String) async throws -> CoreMessage {
        try await call("sendFormattedText") { done in
            self.client.sendFormattedText(chatId: chatId, text: text, elementsJson: elementsJSON, replyTo: replyTo) { message, kind, key in
                done(Self.reply(message.map(Self.message), kind: kind, key: key))
            }
        }
    }

    func editMessage(chatId: String, messageId: String, text: String, elementsJSON: String) async throws -> CoreMessage {
        try await call("editMessage") { done in
            self.client.editMessage(chatId: chatId, messageId: messageId, text: text, elementsJson: elementsJSON) { message, kind, key in
                done(Self.reply(message.map(Self.message), kind: kind, key: key))
            }
        }
    }

    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool, postId: String) async throws -> CoreDeleteResult {
        try await call("deleteMessages") { done in
            self.client.deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone, postId: postId) { result, kind, key in
                done(Self.reply(result.map { CoreDeleteResult(deleted: $0.deleted, failed: $0.failed) }, kind: kind, key: key))
            }
        }
    }

    func saveDraft(chatId: String, text: String, elementsJSON: String, replyTo: String) async throws -> Int64 {
        try await call("saveDraft") { done in
            self.client.saveDraft(chatId: chatId, text: text, elementsJson: elementsJSON, replyTo: replyTo) { time, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(time.int64Value))
                }
            }
        }
    }

    func discardDraft(chatId: String, time: Int64) async throws {
        let _: Void = try await call("discardDraft") { done in
            self.client.discardDraft(chatId: chatId, time: time) { kind, key in
                if let kind { done(.failure(Self.failed(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func serverDrafts() async -> [CoreDraft] {
        client.drafts().map(Self.draft)
    }

    static func draft(_ draft: IosDraft) -> CoreDraft {
        CoreDraft(chatId: draft.chatId, text: draft.text, elementsJSON: draft.elementsJson, replyTo: draft.replyTo, updateTime: draft.updateTime)
    }

    func renameContact(userId: String, firstName: String, lastName: String) async throws -> CoreContact {
        try await call("renameContact") { done in
            self.client.renameContact(userId: userId, firstName: firstName, lastName: lastName) { contact, kind, key in
                done(Self.reply(contact.map(Self.contact), kind: kind, key: key))
            }
        }
    }

    func removeContact(userId: String) async throws -> CoreContact? {
        try await call("removeContact") { done in
            self.client.removeContact(userId: userId) { contact, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(contact.map(Self.contact)))
                }
            }
        }
    }

    func addContactByPhone(phone: String, firstName: String, lastName: String) async throws -> CoreAddedContact {
        try await call("addContactByPhone") { done in
            self.client.addContactByPhone(phone: phone, firstName: firstName, lastName: lastName) { contact, isNew, kind, key in
                let added = contact.map { CoreAddedContact(contact: Self.contact($0), isNew: isNew.boolValue) }
                done(Self.reply(added, kind: kind, key: key))
            }
        }
    }

    func setAddressBook(_ entries: [CorePhoneContact]) async {
        client.setAddressBook(entries: entries.map {
            IosPhoneContact(phone: $0.phone, firstName: $0.firstName, lastName: $0.lastName)
        })
    }

    func setPreferAddressBookNames(_ prefer: Bool) async {
        client.setPreferAddressBookNames(prefer: prefer)
    }

    func loadChatMembers(chatId: String, marker: String, count: Int) async throws -> CoreMembersPage {
        try await call("loadChatMembers") { done in
            self.client.loadChatMembers(chatId: chatId, marker: marker, count: Int32(count)) { page, kind, key in
                let mapped = page.map { CoreMembersPage(members: $0.members.map(Self.member), nextMarker: $0.nextMarker) }
                done(Self.reply(mapped, kind: kind, key: key))
            }
        }
    }

    func searchChatMembers(chatId: String, query: String) async throws -> [CoreGroupMember] {
        try await call("searchChatMembers") { done in
            self.client.searchChatMembers(chatId: chatId, query: query) { members, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success(members.map(Self.member)))
                }
            }
        }
    }

    /// Фильтр ядра работает с его участниками: берутся последние полученные от него объекты.
    /// Хоть одного нет — `nil`, приложение фильтрует само по тому же правилу.
    func filterMembers(_ members: [CoreGroupMember], query: String) async -> [CoreGroupMember]? {
        let known = members.compactMap { MemberCache.shared.member($0.id) }
        guard known.count == members.count else { return nil }
        return client.filterMembers(members: known, query: query).map(Self.member)
    }

    func reconcileDraft(chatId: String, text: String, elementsJSON: String, replyTo: String, updateTime: Int64) async -> CoreDraft? {
        client.reconcileDraft(chatId: chatId, text: text, elementsJson: elementsJSON, replyTo: replyTo, updateTime: updateTime).map(Self.draft)
    }

    func draftDiscardedAt(chatId: String) async -> Int64 {
        client.draftDiscardedAt(chatId: chatId)
    }

    func chatRights(chatId: String) async -> CoreChatRights {
        let rights = client.chatRights(chatId: chatId)
        return CoreChatRights(
            isOwner: rights.isOwner, isAdmin: rights.isAdmin, permissions: rights.permissions,
            canDeleteAnyMessage: rights.canDeleteAnyMessage
        )
    }

    func editTimeoutSeconds() async -> Int64 {
        client.editTimeoutSeconds()
    }

    func deletePlan(chatId: String, messageIds: [String]) async -> CoreDeletePlan? {
        let plan = client.deletePlan(chatId: chatId, messageIds: messageIds)
        return CoreDeletePlan(
            scopes: plan.scopes, canDelete: plan.canDelete, showsForEveryone: plan.showsForEveryone,
            forEveryoneByDefault: plan.forEveryoneByDefault, forcesForEveryone: plan.forcesForEveryone
        )
    }

    func loadPresence(userIds: [String]) async throws -> [CorePresence] {
        try await call("loadPresence") { done in
            self.client.loadPresence(userIds: userIds) { list, kind, key in
                if let kind {
                    done(.failure(Self.failed(kind: kind, key: key)))
                } else {
                    done(.success((list ?? []).map(Self.presence)))
                }
            }
        }
    }

    func presenceOf(userId: String) async -> CorePresence {
        Self.presence(client.presenceOf(userId: userId))
    }

    func setAppActive(_ active: Bool) async {
        client.setAppActive(active: active)
    }

    private static func presence(_ presence: IosPresence) -> CorePresence {
        CorePresence(userId: presence.userId, status: Int(presence.status), seenMs: presence.seenMs)
    }

    private static func member(_ member: IosGroupMember) -> CoreGroupMember {
        MemberCache.shared.keep(member)
        return CoreGroupMember(
            id: member.id, name: member.name, avatarURL: member.avatarUrl, role: member.role,
            alias: member.alias, lastSeenMs: member.lastSeenMs, online: member.online, mentionName: member.mentionName,
            presence: Int(member.presence)
        )
    }

    private static func reply<T>(_ value: T?, kind: String?, key: String?) -> Result<T, Error> {
        if let kind { return .failure(Self.failed(kind: kind, key: key)) }
        guard let value else { return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) }
        return .success(value)
    }
}

/// Последние участники от ядра по id: `filterMembers` моста принимает только его объекты.
private final class MemberCache: @unchecked Sendable {
    static let shared = MemberCache()
    private let lock = NSLock()
    private var members: [String: IosGroupMember] = [:]

    func keep(_ member: IosGroupMember) {
        lock.withLock { members[member.id] = member }
    }

    func member(_ id: String) -> IosGroupMember? {
        lock.withLock { members[id] }
    }
}
