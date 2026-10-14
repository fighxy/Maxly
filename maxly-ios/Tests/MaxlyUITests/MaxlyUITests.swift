import CoreText
import Foundation
import Testing
import SwiftUI
import MaxlyDomain
import MaxlyPresentation
@testable import MaxlyUI

@Suite("Аватар")
struct AvatarInitialsTests {
    @Test("Буквы двух слов, одно слово и пустая строка")
    func initials() {
        #expect(AvatarInitials.text(for: "Ann Lee") == "AL")
        #expect(AvatarInitials.text(for: "ann") == "A")
        #expect(AvatarInitials.text(for: "") == "")
    }

    @Test("Палитра покрывает все номера цвета, отрицательный номер не падает")
    func palette() {
        #expect(AvatarPalette.gradients.count == ChatAvatar.paletteSize)
        _ = AvatarPalette.gradient(-1)
        _ = AvatarPalette.gradient(ChatAvatar.paletteSize * 3 + 2)
    }
}

@Suite("Строка чата")
struct ChatRowPartsTests {
    @Test("Символы доставки")
    func delivery() {
        #expect(DeliveryMark.symbol(for: .sending) == "clock")
        #expect(DeliveryMark.symbol(for: .sent) == "checkmark")
        #expect(DeliveryMark.symbol(for: .read) == "checkmark")
        #expect(DeliveryMark.symbol(for: .failed) == "exclamationmark.circle.fill")
    }

    @Test("Кэш картинок отдаёт сохранённое без сети и чистится")
    func imageCache() async throws {
        let pipeline = ImagePipeline(memoryLimit: 4, directory: nil)
        let url = try #require(URL(string: "https://example.invalid/a.png"))
        #expect(pipeline.cached(url) == nil)
        let image = DecodedImage(PlatformImage())
        await pipeline.store(image, for: url)
        #expect(pipeline.cached(url) === image)
        #expect(await pipeline.image(for: url) === image)
        // Миниатюра того же адреса хранится отдельно и не подменяет крупную картинку.
        let small = DecodedImage(PlatformImage())
        await pipeline.store(small, for: url, maxPixel: 64)
        #expect(pipeline.cached(url, maxPixel: 64) === small)
        #expect(pipeline.cached(url) === image)
        await pipeline.removeAll()
        #expect(pipeline.cached(url) == nil)
    }

    @Test("Картинка на диске переживает перезапуск и стирается вместе с кэшем")
    func diskCache() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "maxly-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://example.invalid/p.jpg?r=abc"))
        let other = try #require(URL(string: "https://example.invalid/p.jpg?r=abd"))
        #expect(ImageDiskCache.name(for: url) == ImageDiskCache.name(for: url))
        #expect(ImageDiskCache.name(for: url) != ImageDiskCache.name(for: other))

        // Папки ещё нет: запись создаёт её сама.
        ImageDiskCache(directory: directory).store(Data("jpeg".utf8), for: url)
        let reopened = ImageDiskCache(directory: directory)
        #expect(reopened.data(for: url) == Data("jpeg".utf8))
        #expect(reopened.data(for: other) == nil)
        reopened.removeAll()
        #expect(reopened.data(for: url) == nil)
    }
}

@Suite("Размер текста в SwiftUI")
struct TextSizeDynamicTypeTests {
    @Test("Каждому шагу свой размер Dynamic Type по возрастанию, стандарт — .large")
    func mapping() {
        let sizes = TextSizeStep.allCases.map(\.dynamicTypeSize)
        #expect(sizes == [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge])
        #expect(sizes == sizes.sorted())
        #expect(Set(sizes).count == sizes.count)
        #expect(TextSizeStep.standard.dynamicTypeSize == .large)
        #expect(sizes.allSatisfy { !$0.isAccessibilitySize })
    }
}

@Suite("Шрифт интерфейса в SwiftUI")
struct TypographyTests {
    @Test("Таблица размеров совпадает со шкалой размера текста, толщины переводятся туда и обратно")
    func tables() {
        for step in TextSizeStep.allCases {
            #expect(Typography.pointSize(.body, step) == CGFloat(step.bodyPointSize))
            #expect(Typography.pointSize(.caption2, step) <= Typography.pointSize(.largeTitle, step))
        }
        #expect(Typography.standardWeight(.headline) == 600)
        #expect(Typography.standardWeight(.subheadline) == 400)
        let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        #expect(weights.map(Typography.numeric) == [100, 200, 300, 400, 500, 600, 700, 800, 900])
        #expect(weights.map { Typography.weight(Typography.numeric($0)) } == weights)
        #expect(Typography.weight(560) == .semibold)
    }

    @Test("Встроенный шрифт берётся из ресурсов с нужной толщиной оси")
    func bundledFont() throws {
        let font = FontFiles.font(file: "inter", size: 17, axis: 560, italic: false)
        #expect(CTFontCopyFamilyName(font) as String == "Inter")
        #expect(CTFontGetSize(font) == 17)
        let variation = try #require(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
        #expect(variation[NSNumber(value: FontFiles.weightAxis)]?.intValue == 560)
        let mono = FontFiles.font(file: FontWeightScale.monoFile, size: 13, axis: 400, italic: false)
        #expect(CTFontCopyFamilyName(mono) as String == "JetBrains Mono")
        for font in AppFont.allCases {
            guard let file = font.file else { continue }
            // У Manrope и Nunito имя начертания по умолчанию — «Manrope ExtraLight»: сверяется начало.
            let family = CTFontCopyFamilyName(FontFiles.font(file: file, size: 15, axis: 500, italic: false)) as String
            #expect(family.hasPrefix(font.title))
        }
    }

    @Test("Применение: те же значения не меняют модель, толщина прижимается к краям")
    func apply() {
        let typography = Typography()
        #expect(!typography.isCustom)
        typography.apply(font: .nunito, weight: 1000, textSize: .xLarge)
        #expect(typography.isCustom)
        #expect(typography.weight == FontWeightScale.max)
        #expect(typography.textSize == .xLarge)
        #expect(typography.platformFont(.body).map { CTFontGetSize($0) } == 19)
        typography.apply(font: .system, weight: 400, textSize: .large)
        #expect(typography.platformFont(.body) == nil)
    }
}
