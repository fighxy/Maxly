import Foundation

/// Как приватный режим прячет данные.
public enum PrivateModeStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// Вместо имён и текста — общие подписи («Личный чат», «Вы получили сообщение»),
    /// вместо аватаров — однотонные круги.
    case placeholder
    /// Настоящие имена, текст и аватары под сильным размытием.
    case blur

    public var title: String {
        switch self {
        case .placeholder: "Заглушки"
        case .blur: "Размытие"
        }
    }
}

/// Приватный режим на этом устройстве. Режим чисто визуальный: сервер о нём не знает,
/// уведомления и данные он не трогает.
public struct PrivateModePreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var style: PrivateModeStyle
    /// Плавающая кнопка «глаз» в списке чатов.
    public var showsQuickToggle: Bool

    public init(isEnabled: Bool = false, style: PrivateModeStyle = .placeholder, showsQuickToggle: Bool = true) {
        self.isEnabled = isEnabled
        self.style = style
        self.showsQuickToggle = showsQuickToggle
    }

    public static let standard = PrivateModePreferences()
}

/// Где лежат настройки приватного режима.
@MainActor
public protocol PrivateModeStore: AnyObject {
    func load() -> PrivateModePreferences
    func save(_ preferences: PrivateModePreferences)
}

/// Настройки только в памяти: для тестов и превью.
@MainActor
public final class InMemoryPrivateModeStore: PrivateModeStore {
    public private(set) var saved: PrivateModePreferences
    public private(set) var saveCount = 0

    public init(_ preferences: PrivateModePreferences = .standard) {
        saved = preferences
    }

    public func load() -> PrivateModePreferences { saved }

    public func save(_ preferences: PrivateModePreferences) {
        saved = preferences
        saveCount += 1
    }
}
