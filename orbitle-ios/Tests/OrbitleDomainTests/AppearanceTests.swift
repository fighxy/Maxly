import Foundation
import Testing
@testable import OrbitleDomain

@Suite("Шкала размера текста")
struct TextSizeStepTests {
    @Test("Семь шагов по возрастанию, от 14 до 23 пт")
    func scale() {
        let steps = TextSizeStep.allCases
        #expect(steps.count == 7)
        #expect(steps.map(\.bodyPointSize) == [14, 15, 16, 17, 19, 21, 23])
        #expect(steps == steps.sorted())
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.bodyPointSize < $1.bodyPointSize })
        #expect(TextSizeStep.maxIndex == 6)
    }

    @Test("По умолчанию 17 пт и 100 %")
    func standard() {
        #expect(TextSizeStep.standard == .large)
        #expect(TextSizeStep.standard.bodyPointSize == 17)
        #expect(TextSizeStep.standard.percent == 100)
        #expect(AppearancePreferences.standard == AppearancePreferences(textSize: .large, theme: .system))
    }

    @Test("Проценты от стандарта и подпись")
    func percent() {
        #expect(TextSizeStep.allCases.map(\.percent) == [82, 88, 94, 100, 112, 124, 135])
        #expect(TextSizeStep.large.caption == "17\u{00A0}пт · 100\u{00A0}%")
        #expect(TextSizeStep.xxxLarge.caption == "23\u{00A0}пт · 135\u{00A0}%")
    }

    @Test("Номер ползунка туда и обратно, края прижимаются")
    func sliderIndex() {
        for step in TextSizeStep.allCases {
            #expect(TextSizeStep(index: step.index) == step)
        }
        #expect(TextSizeStep.xSmall.index == 0)
        #expect(TextSizeStep.large.index == 3)
        #expect(TextSizeStep(index: -5) == .xSmall)
        #expect(TextSizeStep(index: 99) == .xxxLarge)
    }

    @Test("Подписи тем")
    func themes() {
        #expect(ThemeMode.allCases.map(\.title) == ["Системная", "Светлая", "Тёмная"])
        #expect(ThemeMode.allCases.map(\.rawValue) == ["system", "light", "dark"])
    }
}

@Suite("Обои чата")
struct ChatWallpaperTests {
    @Test("По умолчанию без обоев, порядок и подписи для выбора")
    func catalog() {
        #expect(ChatWallpaper.standard == .plain)
        #expect(AppearancePreferences.standard.wallpaper == .plain)
        #expect(!ChatWallpaper.plain.hasImage)
        #expect(ChatWallpaper.allCases.map(\.title) == ["Без обоев", "Осень (авто)", "Осень", "Осень тёмная", "Осень ночь"])
        #expect(ChatWallpaper.allCases.map(\.rawValue) == ["plain", "autumnAuto", "autumn", "autumnDark", "autumnNight"])
    }

    @Test("Картинка: «авто» следует теме, остальные одинаковы в любой теме")
    func images() {
        #expect(ChatWallpaper.plain.imageName(dark: false) == nil)
        #expect(ChatWallpaper.plain.imageName(dark: true) == nil)
        #expect(ChatWallpaper.autumnAuto.imageName(dark: false) == "WallpaperAutumn")
        #expect(ChatWallpaper.autumnAuto.imageName(dark: true) == "WallpaperAutumnDark")
        for wallpaper in [ChatWallpaper.autumn, .autumnDark, .autumnNight] {
            #expect(wallpaper.hasImage)
            #expect(wallpaper.imageName(dark: false) == wallpaper.imageName(dark: true))
        }
        #expect(ChatWallpaper.autumnNight.imageName(dark: false) == "WallpaperAutumnNight")
        #expect(ChatWallpaper.autumnDark.thumbnailName(dark: false) == "WallpaperAutumnDarkThumb")
        #expect(ChatWallpaper.autumnAuto.thumbnailName(dark: true) == "WallpaperAutumnDarkThumb")
        #expect(ChatWallpaper.plain.thumbnailName(dark: false) == nil)
    }
}
