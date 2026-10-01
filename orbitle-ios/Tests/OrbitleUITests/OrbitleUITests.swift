import Foundation
import Testing
import SwiftUI
import OrbitleDomain
import OrbitlePresentation
@testable import OrbitleUI

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
        let directory = FileManager.default.temporaryDirectory.appending(path: "orbitle-images-\(UUID().uuidString)", directoryHint: .isDirectory)
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
