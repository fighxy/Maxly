import Foundation

/// Шаг размера текста: стандартные размеры Dynamic Type без размеров универсального доступа.
///
/// Шаги идут по возрастанию. По умолчанию `.large`: основной текст 17 пт, как в iOS.
public enum TextSizeStep: String, CaseIterable, Comparable, Sendable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge

    public static let standard: TextSizeStep = .large

    /// Номер шага для ползунка: 0 у самого мелкого.
    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Шаг по номеру ползунка. Значения за краями шкалы прижимаются к краю.
    public init(index: Int) {
        let steps = Self.allCases
        self = steps[min(max(index, 0), steps.count - 1)]
    }

    /// Номер последнего шага: правый край ползунка.
    public static var maxIndex: Int { allCases.count - 1 }

    /// Основной текст (`.body`) в пунктах на этом шаге.
    public var bodyPointSize: Int {
        switch self {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        }
    }

    /// Размер относительно стандарта в процентах, с округлением: 82 … 135.
    public var percent: Int {
        Int((Double(bodyPointSize) * 100 / Double(Self.standard.bodyPointSize)).rounded())
    }

    /// Подпись под ползунком: `17 пт · 100 %`.
    public var caption: String {
        "\(bodyPointSize)\u{00A0}пт · \(percent)\u{00A0}%"
    }

    public static func < (lhs: TextSizeStep, rhs: TextSizeStep) -> Bool {
        lhs.index < rhs.index
    }
}

/// Тема оформления: как в системе, всегда светлая или всегда тёмная.
public enum ThemeMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}

/// Настройки оформления на устройстве, общие для всех аккаунтов.
public struct AppearancePreferences: Equatable, Sendable {
    public var textSize: TextSizeStep
    public var theme: ThemeMode

    public init(textSize: TextSizeStep = .standard, theme: ThemeMode = .system) {
        self.textSize = textSize
        self.theme = theme
    }

    public static let standard = AppearancePreferences()
}

/// Где лежат настройки оформления.
@MainActor
public protocol AppearanceStore: AnyObject {
    func load() -> AppearancePreferences
    func save(_ preferences: AppearancePreferences)
}

/// Настройки только в памяти: для тестов и превью.
@MainActor
public final class InMemoryAppearanceStore: AppearanceStore {
    public private(set) var saved: AppearancePreferences
    public private(set) var saveCount = 0

    public init(_ preferences: AppearancePreferences = .standard) {
        saved = preferences
    }

    public func load() -> AppearancePreferences { saved }

    public func save(_ preferences: AppearancePreferences) {
        saved = preferences
        saveCount += 1
    }
}
