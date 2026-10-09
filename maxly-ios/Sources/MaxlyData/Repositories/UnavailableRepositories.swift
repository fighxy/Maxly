import Foundation
import MaxlyDomain

/// Контакты, пока мост ядра (`MaxlyCore`) их не отдаёт: пустой список без возможностей.
/// Экран по `capabilities` показывает, что раздел ещё недоступен.
public struct UnavailableContactRepository: ContactRepository {
    public init() {}

    public var capabilities: ContactCapabilities { [] }

    public func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

/// История звонков, пока мост ядра её не отдаёт.
public struct UnavailableCallHistoryRepository: CallHistoryRepository {
    public init() {}

    public var capabilities: CallCapabilities { [] }

    public func calls() -> AsyncStream<[CallRecord]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

/// Аккаунт до сборки зависимостей: чтение пустое, изменения отклоняются.
public struct UnavailableAccountRepository: AccountRepository {
    public init() {}

    public func profile() async throws(MaxlyError) -> MyProfile { throw .invalidRequest }
    public func updateProfile(firstName: String, lastName: String, about: String) async throws(MaxlyError) -> MyProfile { throw .invalidRequest }
    public func uploadAvatar(jpeg: Data) async throws(MaxlyError) -> MyProfile { throw .invalidRequest }
    public func removeAvatar() async throws(MaxlyError) -> MyProfile { throw .invalidRequest }
    public func deleteAccount() async throws(MaxlyError) -> Date? { throw .invalidRequest }
    public func settings() -> AsyncStream<AccountSettings> { AsyncStream { $0.finish() } }
    public func setPhonePrivacy(_ access: PrivacyAccess) async throws(MaxlyError) -> AccountSettings { throw .invalidRequest }
    public func setOnlineHidden(_ hidden: Bool) async throws(MaxlyError) -> AccountSettings { throw .invalidRequest }
    public func setSafeMode(_ enabled: Bool) async throws(MaxlyError) -> AccountSettings { throw .invalidRequest }
    public func setInactiveTTL(_ ttl: InactiveTTL) async throws(MaxlyError) -> AccountSettings { throw .invalidRequest }
    public func setQuickReaction(_ emoji: String) async throws(MaxlyError) -> AccountSettings { throw .invalidRequest }
    public func sessions() async throws(MaxlyError) -> [DeviceSession] { throw .invalidRequest }
    public func closeOtherSessions() async throws(MaxlyError) { throw .invalidRequest }
    public func approveQrLogin(_ link: String) async throws(MaxlyError) { throw .invalidRequest }
    public func blockedUsers() async throws(MaxlyError) -> [BlockedUser] { throw .invalidRequest }
    public func unblock(userId: String) async throws(MaxlyError) { throw .invalidRequest }
    public func twoFactorStatus() async throws(MaxlyError) -> TwoFactorStatus { throw .invalidRequest }
    public func startEmailChange(password: String) async throws(MaxlyError) -> String { throw .invalidRequest }
    public func sendEmailCode(trackId: String, email: String) async throws(MaxlyError) -> Int { throw .invalidRequest }
    public func confirmEmail(trackId: String, code: String) async throws(MaxlyError) -> TwoFactorStatus { throw .invalidRequest }
    public func launchMiniApp(_ kind: MiniApp.Kind) async throws(MaxlyError) -> MiniApp { throw .invalidRequest }
    public func miniAppCallback(url: URL) async throws(MaxlyError) -> MiniApp { throw .invalidRequest }
}

/// Папки до сборки зависимостей: пустой список, изменения отклоняются.
public struct UnavailableFolderRepository: FolderRepository {
    public init() {}

    public func folders() -> AsyncStream<[ServerFolder]> { AsyncStream { $0.yield([]); $0.finish() } }
    public func reload() async throws(MaxlyError) {}
    public func create(title: String, chatIds: [String], filters: [String]) async throws(MaxlyError) { throw .invalidRequest }
    public func rename(folderId: String, title: String) async throws(MaxlyError) { throw .invalidRequest }
    public func setChats(folderId: String, chatIds: [String]) async throws(MaxlyError) { throw .invalidRequest }
    public func delete(folderId: String) async throws(MaxlyError) { throw .invalidRequest }
    public func reorder(_ folderIds: [String]) async throws(MaxlyError) { throw .invalidRequest }
}

/// Режим призрака и приватность до сборки зависимостей: всё выключено, изменения отклоняются.
public struct UnavailablePrivacyControls: GhostControls, PrivacyControls {
    public init() {}

    public func ghostMode() -> Bool { false }
    public func setGhostMode(_ enabled: Bool) async {}
    public func hideReadReceipts() -> Bool { false }
    public func setHideReadReceipts(_ hidden: Bool) async {}
    public func ghostChanges() -> AsyncStream<GhostState> { AsyncStream { $0.yield(GhostState()); $0.finish() } }
    public func checkOwnPresence() async throws(MaxlyError) -> Contact.Presence { throw .invalidRequest }
    public func localReadMark(chatId: String) -> Int64 { 0 }
    public func privacySettings() -> AsyncStream<AccountSettings> { AsyncStream { $0.finish() } }
    public func setPrivacy(_ key: PrivacyKey, _ value: PrivacyValue) async throws(MaxlyError) -> AccountSettings { throw .invalidRequest }
    public func isPrivacyReadOnly(_ key: PrivacyKey) -> Bool { false }
}
