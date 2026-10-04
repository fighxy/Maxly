import Foundation
import OrbitleDomain

/// Свой аккаунт через ядро: профиль, настройки конфига, сеансы, безопасность, мини-приложения.
public struct CoreAccountRepository: AccountRepository {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func profile() async throws(OrbitleError) -> MyProfile {
        try await run { try await core.loadMyProfile() }
    }

    public func updateProfile(firstName: String, lastName: String, about: String) async throws(OrbitleError) -> MyProfile {
        try await run { try await core.updateProfile(firstName: firstName, lastName: lastName, about: about) }
    }

    public func uploadAvatar(jpeg: Data) async throws(OrbitleError) -> MyProfile {
        try await run { try await core.uploadAvatar(jpeg: jpeg) }
    }

    public func removeAvatar() async throws(OrbitleError) -> MyProfile {
        try await run { try await core.removeAvatar() }
    }

    public func deleteAccount() async throws(OrbitleError) -> Date? {
        let ms = try await run { try await core.deleteAccount() }
        return ms > 0 ? Date(unixMillis: ms) : nil
    }

    public func settings() -> AsyncStream<AccountSettings> {
        core.accountSettings()
    }

    public func setPhonePrivacy(_ access: PrivacyAccess) async throws(OrbitleError) -> AccountSettings {
        try await run { try await core.setPhonePrivacy(access) }
    }

    public func setOnlineHidden(_ hidden: Bool) async throws(OrbitleError) -> AccountSettings {
        try await run { try await core.setOnlineHidden(hidden) }
    }

    public func setSafeMode(_ enabled: Bool) async throws(OrbitleError) -> AccountSettings {
        try await run { try await core.setSafeMode(enabled) }
    }

    public func setInactiveTTL(_ ttl: InactiveTTL) async throws(OrbitleError) -> AccountSettings {
        try await run { try await core.setInactiveTTL(ttl) }
    }

    public func setQuickReaction(_ emoji: String) async throws(OrbitleError) -> AccountSettings {
        try await run { try await core.setQuickReaction(emoji) }
    }

    public func sessions() async throws(OrbitleError) -> [DeviceSession] {
        let list = try await run { try await core.loadSessions() }
        // Текущий первым, остальные от недавних к давним.
        return list.sorted { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent }
            return (a.lastSeen ?? .distantPast) > (b.lastSeen ?? .distantPast)
        }
    }

    public func closeOtherSessions() async throws(OrbitleError) {
        try await run { try await core.closeOtherSessions() }
    }

    public func approveQrLogin(_ link: String) async throws(OrbitleError) {
        try await run { try await core.approveQrLogin(link) }
    }

    public func blockedUsers() async throws(OrbitleError) -> [BlockedUser] {
        try await run { try await core.loadBlockedUsers() }
    }

    public func unblock(userId: String) async throws(OrbitleError) {
        try await run { try await core.unblockUser(userId) }
    }

    public func twoFactorStatus() async throws(OrbitleError) -> TwoFactorStatus {
        try await run { try await core.loadTwoFactor() }
    }

    public func enablePassword(password: String, hint: String) async throws(OrbitleError) {
        do {
            try await core.enablePassword(password: password, hint: hint)
        } catch {
            throw AuthErrors.map(error, during: .password)
        }
    }

    public func changePassword(oldPassword: String, newPassword: String) async throws(OrbitleError) {
        do {
            try await core.changePassword(oldPassword: oldPassword, newPassword: newPassword)
        } catch {
            throw AuthErrors.map(error, during: .password)
        }
    }

    public func disablePassword(password: String) async throws(OrbitleError) {
        do {
            try await core.disablePassword(password: password)
        } catch {
            throw AuthErrors.map(error, during: .password)
        }
    }

    public func startEmailChange(password: String) async throws(OrbitleError) -> String {
        do {
            return try await core.startEmailChange(password: password)
        } catch {
            throw AuthErrors.map(error, during: .password)
        }
    }

    public func sendEmailCode(trackId: String, email: String) async throws(OrbitleError) -> Int {
        do {
            return try await core.sendEmailCode(trackId: trackId, email: email)
        } catch {
            throw Self.rejection(error, "Не удалось отправить код. Проверьте адрес почты")
        }
    }

    public func confirmEmail(trackId: String, code: String) async throws(OrbitleError) -> TwoFactorStatus {
        do {
            return try await core.confirmEmail(trackId: trackId, code: code)
        } catch {
            throw Self.rejection(error, "Неверный код")
        }
    }

    public func launchMiniApp(_ kind: MiniApp.Kind) async throws(OrbitleError) -> MiniApp {
        try await run { try await core.launchMiniApp(kind) }
    }

    public func miniAppCallback(url: URL) async throws(OrbitleError) -> MiniApp {
        try await run { try await core.miniAppCallback(url: url.absoluteString) }
    }

    private func run<T: Sendable>(_ body: () async throws -> T) async throws(OrbitleError) -> T {
        do {
            return try await body()
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    /// Отказ сервера на шаге ввода (почта, код) — понятный текст, остальное общим путём.
    private static func rejection(_ error: Error, _ message: String) -> OrbitleError {
        if let failure = error as? CoreFailure, ["AUTH", "SERVER", "NOT_FOUND"].contains(failure.kind) {
            if failure.key?.lowercased().contains("limit") == true { return .rejected(AuthErrors.tooManyAttempts) }
            return .rejected(message)
        }
        return CoreMapping.apiError(error).orbitleError
    }
}

/// Серверные папки через ядро (`FOLDERS_GET`, `FOLDERS_UPDATE`, `FOLDERS_REORDER`).
public struct CoreFolderRepository: FolderRepository {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func folders() -> AsyncStream<[ServerFolder]> {
        core.folders()
    }

    public func reload() async throws(OrbitleError) {
        _ = try await run { try await core.loadFolders() }
    }

    public func create(title: String, chatIds: [String], filters: [String]) async throws(OrbitleError) {
        try await run { try await core.createFolder(title: title, chatIds: chatIds, filters: filters) }
    }

    public func rename(folderId: String, title: String) async throws(OrbitleError) {
        try await run { try await core.renameFolder(folderId, title: title) }
    }

    public func setChats(folderId: String, chatIds: [String]) async throws(OrbitleError) {
        try await run { try await core.setFolderChats(folderId, chatIds: chatIds) }
    }

    public func delete(folderId: String) async throws(OrbitleError) {
        try await run { try await core.deleteFolder(folderId) }
    }

    public func reorder(_ folderIds: [String]) async throws(OrbitleError) {
        try await run { try await core.reorderFolders(folderIds) }
    }

    private func run<T: Sendable>(_ body: () async throws -> T) async throws(OrbitleError) -> T {
        do {
            return try await body()
        } catch {
            throw CoreMapping.apiError(error).orbitleError
        }
    }
}
