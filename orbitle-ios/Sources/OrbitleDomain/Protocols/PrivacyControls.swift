import Foundation

/// Флаги режима призрака из ядра.
public struct GhostState: Sendable, Hashable {
    /// «Режим призрака»: не появляться в сети и не показывать набор, запись, загрузку и стикеры.
    public var ghostMode: Bool
    /// «Не отправлять отметки о прочтении».
    public var hideReadReceipts: Bool

    public init(ghostMode: Bool = false, hideReadReceipts: Bool = false) {
        self.ghostMode = ghostMode
        self.hideReadReceipts = hideReadReceipts
    }
}

/// Режим призрака и отметки о прочтении (docs/privacy.md).
///
/// Флаги принадлежат ядру и хранятся в нём: оно само шлёт `PING` и `LOGIN` с
/// `interactive: false`, не шлёт `MSG_TYPING` и `CHAT_MARK`, а прочитанное обнуляет локально.
/// Приложение только показывает переключатели и свой статус, поэтому здесь нет ничего про сеть.
public protocol GhostControls: Sendable {
    func ghostMode() -> Bool
    func setGhostMode(_ enabled: Bool) async
    func hideReadReceipts() -> Bool
    func setHideReadReceipts(_ hidden: Bool) async
    /// Текущие флаги сразу и после каждого изменения (события ядра `ghostMode`,
    /// `hideReadReceipts`).
    func ghostChanges() -> AsyncStream<GhostState>
    /// Свой статус глазами сервера: один `CONTACT_PRESENCE` 35 со своим id, мимо кэша.
    func checkOwnPresence() async throws(OrbitleError) -> Contact.Presence
    /// Отметка, до которой чат прочитан только на этом устройстве, пока отметки о прочтении
    /// не отправляются (серверное время сообщения, мс). `0` — такой отметки нет.
    func localReadMark(chatId: String) -> Int64
}

/// Настройки приватности MAX из `config.user` (docs/privacy.md).
public protocol PrivacyControls: Sendable {
    /// Настройки сейчас и после каждого изменения.
    func privacySettings() -> AsyncStream<AccountSettings>
    /// `CONFIG` 22 с одним ключом. Ответ — новые настройки.
    func setPrivacy(_ key: PrivacyKey, _ value: PrivacyValue) async throws(OrbitleError) -> AccountSettings
    /// Ключ сейчас нельзя менять (безопасный режим, семейная защита) — так решает ядро.
    func isPrivacyReadOnly(_ key: PrivacyKey) -> Bool
}

/// «Показывать мой онлайн»: настройка устройства, в ядро не уходит.
public protocol SelfCheckStore: Sendable {
    /// `true`, если пользователь не выключал.
    func showsOwnPresence() -> Bool
    func setShowsOwnPresence(_ shows: Bool)
}
