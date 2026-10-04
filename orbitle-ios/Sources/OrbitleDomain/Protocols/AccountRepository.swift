import Foundation

/// Свой аккаунт на сервере: профиль, настройки, сеансы, безопасность, мини-приложения.
/// Реализация поверх ядра в `OrbitleData`, в тестах — фейк.
public protocol AccountRepository: Sendable {
    func profile() async throws(OrbitleError) -> MyProfile
    /// Пустое `about` очищает «О себе».
    func updateProfile(firstName: String, lastName: String, about: String) async throws(OrbitleError) -> MyProfile
    /// JPEG до 1280 px по длинной стороне.
    func uploadAvatar(jpeg: Data) async throws(OrbitleError) -> MyProfile
    func removeAvatar() async throws(OrbitleError) -> MyProfile
    /// Удаление профиля через 30 дней. Ответ — момент удаления, если сервер его назвал.
    func deleteAccount() async throws(OrbitleError) -> Date?

    /// Настройки сейчас и после каждого изменения.
    func settings() -> AsyncStream<AccountSettings>
    func setPhonePrivacy(_ access: PrivacyAccess) async throws(OrbitleError) -> AccountSettings
    func setOnlineHidden(_ hidden: Bool) async throws(OrbitleError) -> AccountSettings
    func setSafeMode(_ enabled: Bool) async throws(OrbitleError) -> AccountSettings
    func setInactiveTTL(_ ttl: InactiveTTL) async throws(OrbitleError) -> AccountSettings
    /// Быстрая реакция двойного нажатия. Пустую строку сервер не получает.
    func setQuickReaction(_ emoji: String) async throws(OrbitleError) -> AccountSettings

    /// Текущий сеанс первым.
    func sessions() async throws(OrbitleError) -> [DeviceSession]
    func closeOtherSessions() async throws(OrbitleError)
    /// Подтвердить вход на другом устройстве по ссылке из его QR-кода.
    func approveQrLogin(_ link: String) async throws(OrbitleError)

    func blockedUsers() async throws(OrbitleError) -> [BlockedUser]
    func unblock(userId: String) async throws(OrbitleError)

    func twoFactorStatus() async throws(OrbitleError) -> TwoFactorStatus
    func enablePassword(password: String, hint: String) async throws(OrbitleError)
    func changePassword(oldPassword: String, newPassword: String) async throws(OrbitleError)
    func disablePassword(password: String) async throws(OrbitleError)
    /// Начать смену почты: проверка текущего пароля. Ответ — id шага для следующих вызовов.
    func startEmailChange(password: String) async throws(OrbitleError) -> String
    /// Выслать код на `email`. Ответ — через сколько секунд можно выслать снова.
    func sendEmailCode(trackId: String, email: String) async throws(OrbitleError) -> Int
    func confirmEmail(trackId: String, code: String) async throws(OrbitleError) -> TwoFactorStatus

    func launchMiniApp(_ kind: MiniApp.Kind) async throws(OrbitleError) -> MiniApp
    /// Возврат внешнего шага мини-приложения на адрес `url` (`externalCallback=1`).
    func miniAppCallback(url: URL) async throws(OrbitleError) -> MiniApp
}

public extension AccountRepository {
    func enablePassword(password: String, hint: String) async throws(OrbitleError) { throw .invalidRequest }
    func changePassword(oldPassword: String, newPassword: String) async throws(OrbitleError) { throw .invalidRequest }
    func disablePassword(password: String) async throws(OrbitleError) { throw .invalidRequest }
}

/// Серверные папки чатов.
public protocol FolderRepository: Sendable {
    /// Папки в порядке сервера, «Все» первой. Сейчас и после каждого изменения.
    func folders() -> AsyncStream<[ServerFolder]>
    func reload() async throws(OrbitleError)
    func create(title: String, chatIds: [String], filters: [String]) async throws(OrbitleError)
    func rename(folderId: String, title: String) async throws(OrbitleError)
    func setChats(folderId: String, chatIds: [String]) async throws(OrbitleError)
    func delete(folderId: String) async throws(OrbitleError)
    /// Порядок целиком, «Все» первой.
    func reorder(_ folderIds: [String]) async throws(OrbitleError)
}
