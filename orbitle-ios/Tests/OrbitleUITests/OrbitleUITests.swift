import Foundation
import Testing
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
        let pipeline = ImagePipeline(memoryLimit: 4, diskCapacity: 0)
        let url = try #require(URL(string: "https://example.invalid/a.png"))
        #expect(pipeline.cached(url) == nil)
        let image = DecodedImage(PlatformImage())
        await pipeline.store(image, for: url)
        #expect(pipeline.cached(url) === image)
        #expect(await pipeline.image(for: url) === image)
        await pipeline.removeAll()
        #expect(pipeline.cached(url) == nil)
    }
}
