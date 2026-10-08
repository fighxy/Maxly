import Foundation
import OrbitleDomain

/// Режим призрака и приватность в мосте ядра (`MaxIosClient`, docs/privacy.md). Реализация с
/// `import MaxIos` — `MaxIosCore` в приложении, тесты подставляют фейк.
///
/// Сеть целиком на ядре: в режиме призрака оно шлёт `PING` / `LOGIN` с `interactive: false` и
/// не шлёт набор любого вида; без отметок о прочтении `markRead` / `markReadAt` читают чат
/// только на устройстве. Приложению дублировать это не нужно.
public protocol GhostPrivacyCore: Sendable {
    /// `setGhostMode`: флаг хранится в ядре и переживает выход и перезапуск.
    func setGhostMode(_ enabled: Bool) async
    /// `ghostMode()`.
    func ghostMode() -> Bool
    /// `setHideReadReceipts`: отметки не уходят, чат читается только на устройстве.
    func setHideReadReceipts(_ enabled: Bool) async
    /// `hideReadReceipts()`.
    func hideReadReceipts() -> Bool
    /// `localReadMarkOf`: локальная отметка чата (мс), пока отметки скрыты; `0` — нет.
    func localReadMarkOf(chatId: String) -> Int64
    /// `checkOwnPresence`: свежий `CONTACT_PRESENCE` 35 со своим id, мимо кэша. `nil` — сервер
    /// не прислал записи о себе. До входа ядро отвечает ошибкой (или ждёт сессию), поэтому
    /// без своего id его не зовут.
    func checkOwnPresence() async throws -> CorePresence?
    /// Свой id; пусто — вход ещё не выполнен.
    func currentUserId() async -> String
    /// `setPrivacy` для ключей доступа. `NOBODY` ядро принимает только у `PHONE_NUMBER_PRIVACY`;
    /// у поиска по номеру, звонков и приглашений — только `ALL` / `CONTACTS`. Ответ — новые настройки.
    func setPrivacy(key: String, value: String) async throws -> AccountSettings
    /// `setPrivacyFlag` для флагов (`HIDDEN`, `CONTENT_LEVEL_ACCESS`, `SAFE_MODE`).
    func setPrivacyFlag(key: String, enabled: Bool) async throws -> AccountSettings
    /// `isPrivacyReadOnly`: ключ сейчас нельзя менять.
    func isPrivacyReadOnly(key: String) -> Bool
    /// Настройки аккаунта сейчас и после каждого изменения (`watchAccountSettings`).
    func accountSettings() -> AsyncStream<AccountSettings>
    /// События ядра (`watchEvents`); здесь нужны `ghostMode` и `hideReadReceipts`.
    func events() -> AsyncStream<CoreEvent>
}
