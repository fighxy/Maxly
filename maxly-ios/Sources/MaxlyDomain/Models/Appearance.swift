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

/// Обои за лентой чата. Картинки лежат в приложении (`MaxlyApp/Wallpapers`).
///
/// «Осень (авто)» следует теме, как у популярных мессенджеров: в светлой — светлые обои,
/// в тёмной — тёмные. Остальные показываются как есть в любой теме.
public enum ChatWallpaper: String, CaseIterable, Sendable {
    case plain
    case autumnAuto
    case autumn
    case autumnDark
    case autumnNight

    public static let standard: ChatWallpaper = .plain

    public var title: String {
        switch self {
        case .plain: "Без обоев"
        case .autumnAuto: "Осень (авто)"
        case .autumn: "Осень"
        case .autumnDark: "Осень тёмная"
        case .autumnNight: "Осень ночь"
        }
    }

    /// Имя картинки (без `.jpg`) для темы; `nil` — без обоев, фон экрана.
    public func imageName(dark: Bool) -> String? {
        switch self {
        case .plain: nil
        case .autumnAuto: dark ? Self.autumnDark.imageName(dark: dark) : Self.autumn.imageName(dark: dark)
        case .autumn: "WallpaperAutumn"
        case .autumnDark: "WallpaperAutumnDark"
        case .autumnNight: "WallpaperAutumnNight"
        }
    }

    /// Уменьшенная картинка для выбора в «Оформлении».
    public func thumbnailName(dark: Bool) -> String? {
        imageName(dark: dark).map { $0 + "Thumb" }
    }

    public var hasImage: Bool { self != .plain }
}

/// Шрифт интерфейса. Встроенные — переменные (ось толщины `wght`) из `MaxlyUI/Resources/Fonts`,
/// [minWeight]…[maxWeight] — пределы этой оси.
public enum AppFont: String, CaseIterable, Sendable {
    case system
    case inter
    case onest
    case golos
    case manrope
    case nunito

    public var title: String {
        switch self {
        case .system: "Системный"
        case .inter: "Inter"
        case .onest: "Onest"
        case .golos: "Golos Text"
        case .manrope: "Manrope"
        case .nunito: "Nunito"
        }
    }

    /// Имя файла без `.ttf`; у системного — `nil`.
    public var file: String? {
        switch self {
        case .system: nil
        case .inter: "inter"
        case .onest: "onest"
        case .golos: "golos_text"
        case .manrope: "manrope"
        case .nunito: "nunito"
        }
    }

    public var minWeight: Int {
        switch self {
        case .golos: 400
        case .manrope, .nunito: 200
        default: 100
        }
    }

    public var maxWeight: Int {
        switch self {
        case .manrope: 800
        case .nunito: 1000
        default: 900
        }
    }
}

/// Толщина текста: ползунок задаёт толщину обычного текста (по умолчанию 400), остальные начертания
/// сдвигаются на столько же — полужирный остаётся заметно жирнее обычного. У системного шрифта толщина
/// ступенчатая (сотнями), у встроенных — любая в пределах оси файла.
public enum FontWeightScale {
    public static let min = 300
    public static let max = 600
    public static let standard = 400
    /// Блоки кода: моноширинный JetBrains Mono, ось 100…800.
    public static let monoFile = "jetbrains_mono"
    public static let monoRange = 100...800

    public static func clamp(_ base: Int) -> Int { Swift.min(Swift.max(base, min), max) }

    /// Толщина для начертания `requested` (400 обычный, 600 полужирный…) при ползунке `base`.
    public static func axis(_ font: AppFont, requested: Int, base: Int) -> Int {
        let shifted = requested + clamp(base) - standard
        let value = font.file == nil ? Int((Double(shifted) / 100).rounded()) * 100 : shifted
        return Swift.min(Swift.max(value, font.minWeight), font.maxWeight)
    }

    /// Подпись под ползунком: «Обычный · 400».
    public static func caption(_ base: Int) -> String {
        let value = clamp(base)
        let name = switch value {
        case ..<350: "Светлый"
        case ..<450: "Обычный"
        case ..<550: "Средний"
        default: "Полужирный"
        }
        return "\(name)\u{00A0}· \(value)"
    }
}

/// Настройки оформления на устройстве, общие для всех аккаунтов.
public struct AppearancePreferences: Equatable, Sendable {
    public var textSize: TextSizeStep
    public var theme: ThemeMode
    public var wallpaper: ChatWallpaper
    public var font: AppFont
    /// Толщина обычного текста, `FontWeightScale.min…max`.
    public var fontWeight: Int

    public init(
        textSize: TextSizeStep = .standard,
        theme: ThemeMode = .system,
        wallpaper: ChatWallpaper = .standard,
        font: AppFont = .system,
        fontWeight: Int = FontWeightScale.standard
    ) {
        self.textSize = textSize
        self.theme = theme
        self.wallpaper = wallpaper
        self.font = font
        self.fontWeight = FontWeightScale.clamp(fontWeight)
    }

    /// Строка «Шрифт ›» в «Оформлении»: «Inter, 17 пт».
    public var fontSummary: String { "\(font.title), \(textSize.bodyPointSize)\u{00A0}пт" }

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
