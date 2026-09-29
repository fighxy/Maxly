import Foundation
import Observation
import OrbitleDomain

/// Размер текста и тема приложения. Корень приложения следит за ними и применяет их ко всем
/// экранам, экран «Оформление» меняет их.
@MainActor
@Observable
public final class AppearanceSettings {
    public private(set) var textSize: TextSizeStep
    public private(set) var theme: ThemeMode

    @ObservationIgnored private let store: any AppearanceStore

    public init(store: any AppearanceStore) {
        self.store = store
        let saved = store.load()
        textSize = saved.textSize
        theme = saved.theme
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

    private func save() {
        store.save(AppearancePreferences(textSize: textSize, theme: theme))
    }
}
