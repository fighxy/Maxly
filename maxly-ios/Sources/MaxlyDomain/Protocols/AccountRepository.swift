import Foundation

/// Свой аккаунт на сервере: профиль, настройки, сеансы, безопасность, мини-приложения.
/// Реализация поверх ядра в `MaxlyData`, в тестах — фейк.
public protocol AccountRepository: Sendable {
    func profile() async throws(MaxlyError) -> MyProfile
    /// Пустое `about` очищает «О себе».
    func updateProfile(firstName: String, lastName: String, about: String) async throws(MaxlyError) -> MyProfile
    /// JPEG до 1280 px по длинной стороне.
    func uploadAvatar(jpeg: Data) async throws(MaxlyError) -> MyProfile
    func removeAvatar() async throws(MaxlyError) -> MyProfile
    /// Удаление профиля через 30 дней. Ответ — момент удаления, если сервер его назвал.
    func deleteAccount() async throws(MaxlyError) -> Date?

    /// Настройки сейчас и после каждого изменения.
    func settings() -> AsyncStream<AccountSettings>
    func setPhonePrivacy(_ access: PrivacyAccess) async throws(MaxlyError) -> AccountSettings
    func setOnlineHidden(_ hidden: Bool) async throws(MaxlyError) -> AccountSettings
    func setSafeMode(_ enabled: Bool) async throws(MaxlyError) -> AccountSettings
    func setInactiveTTL(_ ttl: InactiveTTL) async throws(MaxlyError) -> AccountSettings
    /// Быстрая реакция двойного нажатия. Пустую строку сервер не получает.
    func setQuickReaction(_ emoji: String) async throws(MaxlyError) -> AccountSettings

    /// Текущий сеанс первым.
    func sessions() async throws(MaxlyError) -> [DeviceSession]
    func closeOtherSessions() async throws(MaxlyError)
    /// Подтвердить вход на другом устройстве по ссылке из его QR-кода.
    func approveQrLogin(_ link: String) async throws(MaxlyError)

    func blockedUsers() async throws(MaxlyError) -> [BlockedUser]
    func unblock(userId: String) async throws(MaxlyError)

    func twoFactorStatus() async throws(MaxlyError) -> TwoFactorStatus
    func enablePassword(password: String, hint: String) async throws(MaxlyError)
    func changePassword(oldPassword: String, newPassword: String) async throws(MaxlyError)
    func disablePassword(password: String) async throws(MaxlyError)
    /// Начать смену почты: проверка текущего пароля. Ответ — id шага для следующих вызовов.
    func startEmailChange(password: String) async throws(MaxlyError) -> String
    /// Выслать код на `email`. Ответ — через сколько секунд можно выслать снова.
    func sendEmailCode(trackId: String, email: String) async throws(MaxlyError) -> Int
    func confirmEmail(trackId: String, code: String) async throws(MaxlyError) -> TwoFactorStatus

    func launchMiniApp(_ kind: MiniApp.Kind) async throws(MaxlyError) -> MiniApp
    /// Возврат внешнего шага мини-приложения на адрес `url` (`externalCallback=1`).
    func miniAppCallback(url: URL) async throws(MaxlyError) -> MiniApp
    /// Мини-приложение бота (`WEB_APP_INIT_DATA` 160): кнопка «Открыть приложение» в чате
    /// или inline-кнопка `OPEN_APP`.
    func launchBotApp(botId: String, chatId: String?, startParam: String?) async throws(MaxlyError) -> MiniApp
}

public extension AccountRepository {
    func launchBotApp(botId: String, chatId: String?, startParam: String?) async throws(MaxlyError) -> MiniApp { throw .invalidRequest }
    func enablePassword(password: String, hint: String) async throws(MaxlyError) { throw .invalidRequest }
    func changePassword(oldPassword: String, newPassword: String) async throws(MaxlyError) { throw .invalidRequest }
    func disablePassword(password: String) async throws(MaxlyError) { throw .invalidRequest }
}

/// Серверные папки чатов.
public protocol FolderRepository: Sendable {
    /// Папки в порядке сервера, «Все» первой. Сейчас и после каждого изменения.
    func folders() -> AsyncStream<[ServerFolder]>
    func reload() async throws(MaxlyError)
    func create(title: String, chatIds: [String], filters: [String]) async throws(MaxlyError)
    func rename(folderId: String, title: String) async throws(MaxlyError)
    func setChats(folderId: String, chatIds: [String]) async throws(MaxlyError)
    func delete(folderId: String) async throws(MaxlyError)
    /// Порядок целиком, «Все» первой.
    func reorder(_ folderIds: [String]) async throws(MaxlyError)
}
