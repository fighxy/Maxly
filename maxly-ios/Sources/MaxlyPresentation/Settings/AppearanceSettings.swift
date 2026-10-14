import Foundation
import Observation
import MaxlyDomain

/// Размер текста, шрифт, тема приложения и обои чата. Корень приложения следит за ними и применяет их ко всем
/// экранам, экран «Оформление» меняет их.
@MainActor
@Observable
public final class AppearanceSettings {
    public private(set) var textSize: TextSizeStep
    public private(set) var theme: ThemeMode
    public private(set) var wallpaper: ChatWallpaper
    public private(set) var font: AppFont
    public private(set) var fontWeight: Int

    @ObservationIgnored private let store: any AppearanceStore

    public init(store: any AppearanceStore) {
        self.store = store
        let saved = store.load()
        textSize = saved.textSize
        theme = saved.theme
        wallpaper = saved.wallpaper
        font = saved.font
        fontWeight = saved.fontWeight
    }

    public var isStandardTextSize: Bool { textSize == .standard }

    public func setTextSize(_ step: TextSizeStep) {
        guard step != textSize else { return }
        textSize = step
        save()
        Log.info(.ui, "Размер текста: \(step.bodyPointSize) пт")
    }

    public func resetTextSize() {
        setTextSize(.standard)
    }

    public func setTheme(_ mode: ThemeMode) {
        guard mode != theme else { return }
        theme = mode
        save()
        Log.info(.ui, "Тема: \(mode.rawValue)")
    }

    public func setWallpaper(_ choice: ChatWallpaper) {
        guard choice != wallpaper else { return }
        wallpaper = choice
        save()
        Log.info(.ui, "Обои чата: \(choice.rawValue)")
    }

    public func setFont(_ choice: AppFont) {
        guard choice != font else { return }
        font = choice
        save()
        Log.info(.ui, "Шрифт: \(choice.rawValue)")
    }

    /// Толщина обычного текста; за пределами `FontWeightScale.min…max` прижимается к краю.
    public func setFontWeight(_ weight: Int) {
        let value = FontWeightScale.clamp(weight)
        guard value != fontWeight else { return }
        fontWeight = value
        save()
    }

    public func resetFontWeight() {
        setFontWeight(FontWeightScale.standard)
    }

    /// Строка «Шрифт ›»: «Inter, 17 пт».
    public var fontSummary: String { preferences.fontSummary }

    private var preferences: AppearancePreferences {
        AppearancePreferences(textSize: textSize, theme: theme, wallpaper: wallpaper, font: font, fontWeight: fontWeight)
    }

    private func save() {
        store.save(preferences)
    }
}
