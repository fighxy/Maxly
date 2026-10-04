import Foundation
import OrbitleDomain

/// Контакты, пока мост ядра (`MaxIos`) их не отдаёт: пустой список без возможностей.
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

    public func profile() async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    public func updateProfile(firstName: String, lastName: String, about: String) async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    public func uploadAvatar(jpeg: Data) async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    public func removeAvatar() async throws(OrbitleError) -> MyProfile { throw .invalidRequest }
    public func deleteAccount() async throws(OrbitleError) -> Date? { throw .invalidRequest }
    public func settings() -> AsyncStream<AccountSettings> { AsyncStream { $0.finish() } }
    public func setPhonePrivacy(_ access: PrivacyAccess) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    public func setOnlineHidden(_ hidden: Bool) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    public func setSafeMode(_ enabled: Bool) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    public func setInactiveTTL(_ ttl: InactiveTTL) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    public func setQuickReaction(_ emoji: String) async throws(OrbitleError) -> AccountSettings { throw .invalidRequest }
    public func sessions() async throws(OrbitleError) -> [DeviceSession] { throw .invalidRequest }
    public func closeOtherSessions() async throws(OrbitleError) { throw .invalidRequest }
    public func approveQrLogin(_ link: String) async throws(OrbitleError) { throw .invalidRequest }
    public func blockedUsers() async throws(OrbitleError) -> [BlockedUser] { throw .invalidRequest }
    public func unblock(userId: String) async throws(OrbitleError) { throw .invalidRequest }
    public func twoFactorStatus() async throws(OrbitleError) -> TwoFactorStatus { throw .invalidRequest }
    public func startEmailChange(password: String) async throws(OrbitleError) -> String { throw .invalidRequest }
    public func sendEmailCode(trackId: String, email: String) async throws(OrbitleError) -> Int { throw .invalidRequest }
    public func confirmEmail(trackId: String, code: String) async throws(OrbitleError) -> TwoFactorStatus { throw .invalidRequest }
    public func launchMiniApp(_ kind: MiniApp.Kind) async throws(OrbitleError) -> MiniApp { throw .invalidRequest }
    public func miniAppCallback(url: URL) async throws(OrbitleError) -> MiniApp { throw .invalidRequest }
}

/// Папки до сборки зависимостей: пустой список, изменения отклоняются.
public struct UnavailableFolderRepository: FolderRepository {
    public init() {}

    public func folders() -> AsyncStream<[ServerFolder]> { AsyncStream { $0.yield([]); $0.finish() } }
    public func reload() async throws(OrbitleError) {}
    public func create(title: String, chatIds: [String], filters: [String]) async throws(OrbitleError) { throw .invalidRequest }
    public func rename(folderId: String, title: String) async throws(OrbitleError) { throw .invalidRequest }
    public func setChats(folderId: String, chatIds: [String]) async throws(OrbitleError) { throw .invalidRequest }
    public func delete(folderId: String) async throws(OrbitleError) { throw .invalidRequest }
    public func reorder(_ folderIds: [String]) async throws(OrbitleError) { throw .invalidRequest }
}
