import Foundation
import Observation
import MaxlyDomain

/// Размер текста, тема приложения и обои чата. Корень приложения следит за ними и применяет их ко всем
/// экранам, экран «Оформление» меняет их.
@MainActor
@Observable
public final class AppearanceSettings {
    public private(set) var textSize: TextSizeStep
    public private(set) var theme: ThemeMode
    public private(set) var wallpaper: ChatWallpaper

    @ObservationIgnored private let store: any AppearanceStore

    public init(store: any AppearanceStore) {
        self.store = store
        let saved = store.load()
        textSize = saved.textSize
        theme = saved.theme
        wallpaper = saved.wallpaper
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

    private func save() {
        store.save(AppearancePreferences(textSize: textSize, theme: theme, wallpaper: wallpaper))
    }
}
