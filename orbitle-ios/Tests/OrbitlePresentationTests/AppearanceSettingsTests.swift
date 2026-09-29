import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Оформление")
@MainActor
struct AppearanceSettingsTests {
    @Test("Модель читает сохранённое")
    func loads() {
        let store = InMemoryAppearanceStore(AppearancePreferences(textSize: .xLarge, theme: .light))
        let settings = AppearanceSettings(store: store)
        #expect(settings.textSize == .xLarge)
        #expect(settings.theme == .light)
        #expect(!settings.isStandardTextSize)
    }

    @Test("Шаг и тема сохраняются, повтор того же значения не пишет")
    func saves() {
        let store = InMemoryAppearanceStore()
        let settings = AppearanceSettings(store: store)
        #expect(settings.isStandardTextSize)
        settings.setTextSize(.xxxLarge)
        #expect(store.saved == AppearancePreferences(textSize: .xxxLarge, theme: .system))
        settings.setTheme(.dark)
        #expect(store.saved == AppearancePreferences(textSize: .xxxLarge, theme: .dark))
        #expect(store.saveCount == 2)
        settings.setTheme(.dark)
        settings.setTextSize(.xxxLarge)
        #expect(store.saveCount == 2)
        let again = AppearanceSettings(store: store)
        #expect(again.textSize == .xxxLarge)
        #expect(again.theme == .dark)
    }

    @Test("Сброс возвращает 17 пт и не трогает тему")
    func reset() {
        let store = InMemoryAppearanceStore(AppearancePreferences(textSize: .xSmall, theme: .dark))
        let settings = AppearanceSettings(store: store)
        settings.resetTextSize()
        #expect(settings.textSize == .standard)
        #expect(settings.textSize.bodyPointSize == 17)
        #expect(settings.theme == .dark)
        #expect(store.saved == AppearancePreferences(textSize: .large, theme: .dark))
    }
}
