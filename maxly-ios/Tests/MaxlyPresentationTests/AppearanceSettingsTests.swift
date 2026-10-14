import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

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

    @Test("Обои сохраняются вместе с размером и темой, повтор не пишет, другие настройки их не сбрасывают")
    func wallpaper() {
        let store = InMemoryAppearanceStore(AppearancePreferences(textSize: .small, theme: .light))
        let settings = AppearanceSettings(store: store)
        #expect(settings.wallpaper == .plain)
        settings.setWallpaper(.autumnNight)
        #expect(settings.wallpaper == .autumnNight)
        #expect(store.saved == AppearancePreferences(textSize: .small, theme: .light, wallpaper: .autumnNight))
        settings.setWallpaper(.autumnNight)
        #expect(store.saveCount == 1)
        settings.setTheme(.dark)
        settings.resetTextSize()
        #expect(store.saved == AppearancePreferences(textSize: .large, theme: .dark, wallpaper: .autumnNight))
        let again = AppearanceSettings(store: store)
        #expect(again.wallpaper == .autumnNight)
        settings.setWallpaper(.plain)
        #expect(store.saved.wallpaper == .plain)
    }

    @Test("Шрифт и толщина сохраняются вместе с остальным, толщина прижимается к краям")
    func font() {
        let store = InMemoryAppearanceStore(AppearancePreferences(textSize: .small, theme: .dark))
        let settings = AppearanceSettings(store: store)
        #expect(settings.font == .system)
        #expect(settings.fontWeight == FontWeightScale.standard)
        settings.setFont(.onest)
        settings.setFontWeight(450)
        #expect(store.saved == AppearancePreferences(textSize: .small, theme: .dark, font: .onest, fontWeight: 450))
        #expect(settings.fontSummary == "Onest, 15\u{00A0}пт")
        settings.setFontWeight(9000)
        #expect(settings.fontWeight == FontWeightScale.max)
        let count = store.saveCount
        settings.setFont(.onest)
        settings.setFontWeight(700)
        #expect(store.saveCount == count)
        settings.resetFontWeight()
        settings.resetTextSize()
        #expect(store.saved == AppearancePreferences(textSize: .large, theme: .dark, font: .onest))
        #expect(AppearanceSettings(store: store).font == .onest)
    }
}
