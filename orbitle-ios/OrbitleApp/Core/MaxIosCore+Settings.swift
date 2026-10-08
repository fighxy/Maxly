import Foundation
import OrbitleData
import OrbitleDomain
import MaxIos

/// Настройки аккаунта, режим призрака и приватность через `MaxIosClient` (docs/settings.md,
/// docs/privacy.md).
/// Числа в колбэках Kotlin приходят упакованными (`KotlinLong`, `KotlinInt`).
extension MaxIosCore {
    func loadMyProfile() async throws -> MyProfile {
        try await call("loadMyProfile") { done in
            self.client.loadMyProfile { done(Self.profileResult($0, $1, $2)) }
        }
    }

    func updateProfile(firstName: String, lastName: String, about: String) async throws -> MyProfile {
        try await call("updateProfile") { done in
            self.client.updateProfile(firstName: firstName, lastName: lastName, description: about) {
                done(Self.profileResult($0, $1, $2))
            }
        }
    }

    func uploadAvatar(jpeg: Data) async throws -> MyProfile {
        try await call("uploadAvatar") { done in
            self.client.uploadAvatar(image: jpeg) { done(Self.profileResult($0, $1, $2)) }
        }
    }

    func removeAvatar() async throws -> MyProfile {
        try await call("removeAvatar") { done in
            self.client.removeAvatar { done(Self.profileResult($0, $1, $2)) }
        }
    }

    func deleteAccount() async throws -> Int64 {
        try await call("deleteAccount") { done in
            self.client.deleteAccount { ms, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(ms.int64Value))
                }
            }
        }
    }

    func accountSettings() -> AsyncStream<AccountSettings> {
        AsyncStream { continuation in
            continuation.yield(Self.settings(client.accountSettings()))
            let watch = WatchBox(client.watchAccountSettings { value in
                continuation.yield(Self.settings(value))
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    func setPhonePrivacy(_ access: PrivacyAccess) async throws -> AccountSettings {
        try await call("setPhonePrivacy") { done in
            self.client.setPhonePrivacy(value: access.rawValue) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    func setOnlineHidden(_ hidden: Bool) async throws -> AccountSettings {
        try await call("setOnlineHidden") { done in
            self.client.setOnlineHidden(hidden: hidden) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    func setSafeMode(_ enabled: Bool) async throws -> AccountSettings {
        try await call("setSafeMode") { done in
            self.client.setSafeMode(enabled: enabled) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    // MARK: Режим призрака и приватность (docs/privacy.md)

    func setGhostMode(_ enabled: Bool) async {
        client.setGhostMode(enabled: enabled)
    }

    func ghostMode() -> Bool {
        client.ghostMode()
    }

    func setHideReadReceipts(_ enabled: Bool) async {
        client.setHideReadReceipts(enabled: enabled)
    }

    func hideReadReceipts() -> Bool {
        client.hideReadReceipts()
    }

    func localReadMarkOf(chatId: String) -> Int64 {
        client.localReadMarkOf(chatId: chatId)
    }

    /// Свежий `CONTACT_PRESENCE` 35 со своим id. `nil` и без ошибки — сервер о себе промолчал.
    func checkOwnPresence() async throws -> CorePresence? {
        try await call("checkOwnPresence") { done in
            self.client.checkOwnPresence { presence, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(presence.map {
                        CorePresence(userId: $0.userId, status: Int($0.status), seenMs: $0.seenMs)
                    }))
                }
            }
        }
    }

    func setPrivacy(key: String, value: String) async throws -> AccountSettings {
        try await call("setPrivacy") { done in
            self.client.setPrivacy(key: key, value: value) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    func setPrivacyFlag(key: String, enabled: Bool) async throws -> AccountSettings {
        try await call("setPrivacyFlag") { done in
            self.client.setPrivacyFlag(key: key, enabled: enabled) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    func isPrivacyReadOnly(key: String) -> Bool {
        client.isPrivacyReadOnly(key: key)
    }

    func setInactiveTTL(_ ttl: InactiveTTL) async throws -> AccountSettings {
        try await call("setInactiveTtl") { done in
            self.client.setInactiveTtl(value: ttl.rawValue) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    func setQuickReaction(_ emoji: String) async throws -> AccountSettings {
        try await call("setQuickReaction") { done in
            self.client.setQuickReaction(emoji: emoji) { done(Self.settingsResult($0, $1, $2)) }
        }
    }

    func loadSessions() async throws -> [DeviceSession] {
        try await call("loadSessions") { done in
            self.client.loadSessions { sessions, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(sessions.map(Self.session)))
                }
            }
        }
    }

    func closeOtherSessions() async throws {
        let _: Void = try await call("closeOtherSessions") { done in
            self.client.closeOtherSessions { done(Self.voidResult($0, $1)) }
        }
    }

    func approveQrLogin(_ link: String) async throws {
        let _: Void = try await call("approveQrLogin") { done in
            self.client.approveQrLogin(qrLink: link) { done(Self.voidResult($0, $1)) }
        }
    }

    func loadBlockedUsers() async throws -> [BlockedUser] {
        try await call("loadBlockedUsers") { done in
            self.client.loadBlockedUsers { users, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(users.map {
                        BlockedUser(id: $0.id, name: $0.name, phone: $0.phone, avatarURL: URL(string: $0.avatarUrl))
                    }))
                }
            }
        }
    }

    func unblockUser(_ userId: String) async throws {
        let _: Void = try await call("unblockUser") { done in
            self.client.unblockUser(userId: userId) { done(Self.voidResult($0, $1)) }
        }
    }

    func blockUser(_ userId: String) async throws {
        let _: Void = try await call("blockUser") { done in
            self.client.blockUser(userId: userId) { done(Self.voidResult($0, $1)) }
        }
    }

    func commonChats(userId: String) async throws -> [CommonChat] {
        try await call("commonChats") { done in
            self.client.commonChats(userId: userId) { chats, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(chats.map {
                        CommonChat(
                            id: $0.id,
                            title: $0.title,
                            isChannel: $0.type == "CHANNEL",
                            avatarURL: $0.iconUrl.isEmpty ? nil : URL(string: $0.iconUrl),
                            participants: Int($0.participants)
                        )
                    }))
                }
            }
        }
    }

    func complaintReasons(typeId: Int) async throws -> [ComplaintReason] {
        try await call("complaintReasons") { done in
            self.client.complaintReasons(typeId: Int32(typeId)) { reasons, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(reasons.map { ComplaintReason(id: Int($0.id), title: $0.title) }))
                }
            }
        }
    }

    func sendComplaint(reasonId: Int, typeId: Int, ids: [String]) async throws -> Bool {
        try await call("sendComplaint") { done in
            self.client.sendComplaint(reasonId: Int32(reasonId), typeId: Int32(typeId), ids: ids) { result, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(result == "ok"))
                }
            }
        }
    }

    func syncContacts() async throws -> [CoreContact] {
        try await call("syncContacts") { done in
            self.client.syncContacts { contacts, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(contacts.map(Self.contact)))
                }
            }
        }
    }

    func enablePassword(password: String, hint: String) async throws {
        let _: Void = try await call("enablePassword") { done in
            self.client.enablePassword(password: password, hint: hint) { kind, key in
                if let kind { done(.failure(CoreFailure(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        let _: Void = try await call("changePassword") { done in
            self.client.changePassword(oldPassword: oldPassword, newPassword: newPassword) { kind, key in
                if let kind { done(.failure(CoreFailure(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func disablePassword(password: String) async throws {
        let _: Void = try await call("disablePassword") { done in
            self.client.disablePassword(password: password) { kind, key in
                if let kind { done(.failure(CoreFailure(kind: kind, key: key))) } else { done(.success(())) }
            }
        }
    }

    func loadTwoFactor() async throws -> TwoFactorStatus {
        try await call("loadTwoFactor") { done in
            self.client.loadTwoFactor { done(Self.twoFactorResult($0, $1, $2)) }
        }
    }

    func startEmailChange(password: String) async throws -> String {
        try await call("startEmailChange") { done in
            self.client.startEmailChange(password: password) { trackId, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else if let trackId, !trackId.isEmpty {
                    done(.success(trackId))
                } else {
                    done(.failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)))
                }
            }
        }
    }

    func sendEmailCode(trackId: String, email: String) async throws -> Int {
        try await call("sendEmailCode") { done in
            self.client.sendEmailCode(trackId: trackId, email: email) { seconds, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(Int(seconds.int32Value)))
                }
            }
        }
    }

    func confirmEmail(trackId: String, code: String) async throws -> TwoFactorStatus {
        try await call("confirmEmail") { done in
            self.client.confirmEmail(trackId: trackId, code: code) { done(Self.twoFactorResult($0, $1, $2)) }
        }
    }

    func launchMiniApp(_ kind: MiniApp.Kind) async throws -> MiniApp {
        try await call("launchMiniApp") { done in
            self.client.launchMiniApp(app: kind.rawValue) { done(Self.miniAppResult($0, $1, $2)) }
        }
    }

    func launchBotApp(botId: String, chatId: String, startParam: String) async throws -> MiniApp {
        try await call("launchBotApp") { done in
            self.client.launchBotApp(botId: botId, chatId: chatId, startParam: startParam) { done(Self.miniAppResult($0, $1, $2)) }
        }
    }

    func miniAppCallback(url: String) async throws -> MiniApp {
        try await call("miniAppCallback") { done in
            self.client.miniAppCallback(url: url) { done(Self.miniAppResult($0, $1, $2)) }
        }
    }

    func folders() -> AsyncStream<[ServerFolder]> {
        AsyncStream { continuation in
            let watch = WatchBox(client.watchFolders { folders in
                continuation.yield(folders.map(Self.folder))
            })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    func loadFolders() async throws -> [ServerFolder] {
        try await call("loadFolders") { done in
            self.client.loadFolders { folders, kind, key in
                if let kind {
                    done(.failure(CoreFailure(kind: kind, key: key)))
                } else {
                    done(.success(folders.map(Self.folder)))
                }
            }
        }
    }

    func createFolder(title: String, chatIds: [String], filters: [String]) async throws {
        let _: Void = try await call("createFolder") { done in
            self.client.createFolder(title: title, chatIds: chatIds, filters: filters) { done(Self.voidResult($0, $1)) }
        }
    }

    func renameFolder(_ folderId: String, title: String) async throws {
        let _: Void = try await call("renameFolder") { done in
            self.client.renameFolder(folderId: folderId, title: title) { done(Self.voidResult($0, $1)) }
        }
    }

    func setFolderChats(_ folderId: String, chatIds: [String]) async throws {
        let _: Void = try await call("setFolderChats") { done in
            self.client.setFolderChats(folderId: folderId, chatIds: chatIds) { done(Self.voidResult($0, $1)) }
        }
    }

    func deleteFolder(_ folderId: String) async throws {
        let _: Void = try await call("deleteFolder") { done in
            self.client.deleteFolder(folderId: folderId) { done(Self.voidResult($0, $1)) }
        }
    }

    func reorderFolders(_ order: [String]) async throws {
        let _: Void = try await call("reorderFolders") { done in
            self.client.reorderFolders(order: order) { done(Self.voidResult($0, $1)) }
        }
    }

    // MARK: Преобразования

    private static func voidResult(_ kind: String?, _ key: String?) -> Result<Void, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        return .success(())
    }

    private static func profileResult(_ value: IosMyProfile?, _ kind: String?, _ key: String?) -> Result<MyProfile, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        guard let value else { return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) }
        return .success(MyProfile(
            id: value.id,
            firstName: value.firstName,
            lastName: value.lastName,
            about: value.description_,
            phone: value.phone,
            avatarURL: value.avatarUrl.isEmpty ? nil : URL(string: value.avatarUrl),
            hasPhoto: !value.photoId.isEmpty || !value.avatarUrl.isEmpty,
            link: value.link.isEmpty ? nil : URL(string: value.link)
        ))
    }

    private static func settingsResult(_ value: IosAccountSettings?, _ kind: String?, _ key: String?) -> Result<AccountSettings, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        guard let value else { return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) }
        return .success(settings(value))
    }

    private static func settings(_ value: IosAccountSettings) -> AccountSettings {
        AccountSettings(
            isKnown: value.known,
            // Ядро уже подставило значения веб-клиента MAX для ключей, которых сервер не прислал,
            // и привело `_NONE_` к `NOBODY`; запасные значения здесь — те же.
            phonePrivacy: PrivacyAccess(rawValue: value.phonePrivacy) ?? .contacts,
            onlineHidden: value.onlineHidden,
            safeMode: value.safeMode,
            searchByPhone: PrivacyAccess(rawValue: value.searchByPhone) ?? .everybody,
            incomingCall: PrivacyAccess(rawValue: value.incomingCalls) ?? .everybody,
            chatsInvite: PrivacyAccess(rawValue: value.chatInvites) ?? .everybody,
            safeContentOnly: value.safeContentOnly,
            // Имя `FamilyProtection` ядра: `OFF`, `ADMIN`, `MANAGEABLE` или `UNKNOWN`.
            familyProtection: FamilyProtection(rawValue: value.familyProtection) ?? .unknown,
            familyProtectionRaw: value.familyProtectionRaw,
            privacyLocked: value.privacyLocked,
            showReadMark: value.showReadMarkKnown ? value.showReadMark : nil,
            inactiveTTL: InactiveTTL(rawValue: value.inactiveTtl) ?? .sixMonths,
            inviteLink: value.inviteLink.isEmpty ? nil : URL(string: value.inviteLink),
            sferumBotId: value.sferumBotId,
            digitalIdBotId: value.digitalIdBotId,
            quickReaction: value.quickReaction.isEmpty ? AccountSettings.defaultQuickReaction : value.quickReaction,
            quickReactionEnabled: !value.quickReactionDisabled
        )
    }

    private static func session(_ value: IosSession) -> DeviceSession {
        DeviceSession(
            id: value.id,
            client: value.client,
            info: value.info,
            location: value.location,
            isCurrent: value.current,
            lastSeen: value.lastSeenMs > 0 ? Date(timeIntervalSince1970: Double(value.lastSeenMs) / 1000) : nil
        )
    }

    private static func twoFactorResult(_ value: IosTwoFactor?, _ kind: String?, _ key: String?) -> Result<TwoFactorStatus, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        guard let value else { return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) }
        return .success(TwoFactorStatus(isEnabled: value.enabled, email: value.email, hint: value.hint))
    }

    private static func miniAppResult(_ value: IosMiniApp?, _ kind: String?, _ key: String?) -> Result<MiniApp, Error> {
        if let kind { return .failure(CoreFailure(kind: kind, key: key)) }
        guard let value, let url = URL(string: value.url) else {
            return .failure(CoreFailure(kind: "MALFORMED_REPLY", key: nil))
        }
        return .success(MiniApp(botId: value.botId, url: url, queryId: value.queryId.isEmpty ? nil : value.queryId))
    }

    private static func folder(_ value: IosFolder) -> ServerFolder {
        ServerFolder(
            id: value.id,
            title: value.title,
            chatIds: value.chatIds,
            filters: value.filters,
            isAllChats: value.isAllChats
        )
    }
}

/// Мост для `CoreGhostPrivacyControls`: методы выше, `accountSettings()`, `events()` и
/// `currentUserId()`.
extension MaxIosCore: GhostPrivacyCore {}
