import Foundation

/// Семейная защита (`FAMILY_PROTECTION` в `config.user`): строка `OFF`, `ADMIN` или `MANAGEABLE`.
public enum FamilyProtection: String, Sendable, Hashable, CaseIterable {
    case off = "OFF"
    /// Вы администратор: управляете чужим профилем.
    case admin = "ADMIN"
    /// Профилем управляет администратор: часть настроек приватности заблокирована.
    case manageable = "MANAGEABLE"

    /// Значение сервера в любом регистре; незнакомое (в том числе старое `ON`) — «Отключена».
    public init(wire: String) {
        self = FamilyProtection(rawValue: wire.trimmingCharacters(in: .whitespaces).uppercased()) ?? .off
    }

    public var title: String {
        switch self {
        case .off: "Отключена"
        case .admin: "Вы администратор"
        case .manageable: "Профиль под защитой"
        }
    }
}

/// Ключ настройки приватности в `config.user`. Изменение — `CONFIG` 22
/// `{settings:{user:{<ключ>: <значение>}}}`. `FAMILY_PROTECTION` только читается и здесь не нужен.
public enum PrivacyKey: String, Sendable, Hashable, CaseIterable {
    case searchByPhone = "SEARCH_BY_PHONE"
    case incomingCall = "INCOMING_CALL"
    case chatsInvite = "CHATS_INVITE"
    case contentLevelAccess = "CONTENT_LEVEL_ACCESS"
    case safeMode = "SAFE_MODE"
    case hidden = "HIDDEN"
    case phoneNumberPrivacy = "PHONE_NUMBER_PRIVACY"

    /// Ключи, которые блокирует безопасный режим и семейная защита (`MANAGEABLE`).
    public static let guarded: Set<PrivacyKey> = [.searchByPhone, .incomingCall, .chatsInvite, .contentLevelAccess]

    /// Значение флага или доступа: флаги — `CONTENT_LEVEL_ACCESS`, `SAFE_MODE`, `HIDDEN`.
    public var isFlag: Bool {
        switch self {
        case .contentLevelAccess, .safeMode, .hidden: true
        case .searchByPhone, .incomingCall, .chatsInvite, .phoneNumberPrivacy: false
        }
    }
}

/// Значение настройки приватности: доступ (`ALL` / `CONTACTS` / `NOBODY`) или флаг.
public enum PrivacyValue: Sendable, Hashable {
    case access(PrivacyAccess)
    case flag(Bool)

    /// Как значение уходит на сервер: строка доступа или `true` / `false`.
    public var wire: String {
        switch self {
        case .access(let access): access.rawValue
        case .flag(let flag): flag ? "true" : "false"
        }
    }
}

public extension AccountSettings {
    /// Текущее значение ключа.
    func value(for key: PrivacyKey) -> PrivacyValue {
        switch key {
        case .searchByPhone: .access(searchByPhone)
        case .incomingCall: .access(incomingCall)
        case .chatsInvite: .access(chatsInvite)
        case .contentLevelAccess: .flag(safeContentOnly)
        case .safeMode: .flag(safeMode)
        case .hidden: .flag(onlineHidden)
        case .phoneNumberPrivacy: .access(phonePrivacy)
        }
    }

    /// Записать значение ключа. Значение не того вида (флаг для доступа и наоборот) не меняет ничего.
    mutating func set(_ key: PrivacyKey, _ value: PrivacyValue) {
        switch (key, value) {
        case (.searchByPhone, .access(let access)): searchByPhone = access
        case (.incomingCall, .access(let access)): incomingCall = access
        case (.chatsInvite, .access(let access)): chatsInvite = access
        case (.phoneNumberPrivacy, .access(let access)): phonePrivacy = access
        case (.contentLevelAccess, .flag(let flag)): safeContentOnly = flag
        case (.safeMode, .flag(let flag)): safeMode = flag
        case (.hidden, .flag(let flag)): onlineHidden = flag
        default: break
        }
    }

    /// Копия с одним изменённым ключом.
    func setting(_ key: PrivacyKey, _ value: PrivacyValue) -> AccountSettings {
        var copy = self
        copy.set(key, value)
        return copy
    }
}
