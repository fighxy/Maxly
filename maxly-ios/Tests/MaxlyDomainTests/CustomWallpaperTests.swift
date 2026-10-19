import Foundation
import Testing
@testable import MaxlyDomain

@Suite("Свои обои: выбор и формат")
struct CustomWallpaperTests {
    private let global = CustomWallpaper(file: "global-a.jpg", dim: 0.2)
    private let own = CustomWallpaper(file: "chat-1-b.jpg", dim: 0.3)

    @Test("Сначала обои чата, потом общие, потом встроенные")
    func resolution() {
        var index = CustomWallpaperIndex()
        #expect(index.resolve(chatId: "1") == nil)
        #expect(index.resolve(chatId: nil) == nil)
        index[.global] = global
        #expect(index.resolve(chatId: "1") == global)
        #expect(index.resolve(chatId: nil) == global)
        index[.chat("1")] = own
        #expect(index.resolve(chatId: "1") == own)
        #expect(index.resolve(chatId: "2") == global)
        index[.global] = nil
        #expect(index.resolve(chatId: "2") == nil)
        #expect(index.resolve(chatId: "1") == own)
        #expect(index.files == ["chat-1-b.jpg"])
    }

    @Test("Затемнение и размытие прижимаются к пределам, в тёмной теме затемнение выше")
    func clamping() {
        let dark = CustomWallpaper(file: "x.jpg", dim: 5, blur: -1)
        #expect(dark.dim == CustomWallpaper.dimRange.upperBound)
        #expect(dark.blur == 0)
        #expect(CustomWallpaper(file: "x.jpg", dim: .nan).dim == CustomWallpaper.defaultDim)
        #expect(CustomWallpaper.dimOpacity(0, dark: false) == 0)
        #expect(abs(CustomWallpaper.dimOpacity(0, dark: true) - 0.3) < 0.0001)
        #expect(abs(CustomWallpaper.dimOpacity(0.5, dark: true) - 0.65) < 0.0001)
        #expect(CustomWallpaper.dimOpacity(0.5, dark: true) > CustomWallpaper.dimOpacity(0.5, dark: false))
        #expect(CustomWallpaper.blurRadius(1) == CustomWallpaper.maxBlurRadius)
        #expect(CustomWallpaper.percent(0.4) == "40\u{00A0}%")
    }

    @Test("Список читается и пишется в JSON с ключами global и chats, время — секунды Unix")
    func json() throws {
        let index = CustomWallpaperIndex(
            global: CustomWallpaper(file: "global-a.jpg", dim: 0.1, blur: 0.5, updatedAt: Date(timeIntervalSince1970: 100)),
            chats: ["-42": CustomWallpaper(file: "chat--42-b.jpg", dim: 0.3, blur: 0, updatedAt: Date(timeIntervalSince1970: 200))]
        )
        let data = try JSONEncoder().encode(index)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let globalObject = try #require(object["global"] as? [String: Any])
        #expect(globalObject["file"] as? String == "global-a.jpg")
        #expect(globalObject["updatedAt"] as? Double == 100)
        let chats = try #require(object["chats"] as? [String: Any])
        #expect(chats["-42"] != nil)
        #expect(try JSONDecoder().decode(CustomWallpaperIndex.self, from: data) == index)
    }

    @Test("Запись без необязательных полей читается со значениями по умолчанию")
    func lenientDecoding() throws {
        let json = #"{"chats":{"7":{"file":"chat-7-c.jpg"}}}"#
        let index = try JSONDecoder().decode(CustomWallpaperIndex.self, from: Data(json.utf8))
        #expect(index.version == CustomWallpaperIndex.currentVersion)
        #expect(index.global == nil)
        #expect(index.chats["7"]?.dim == CustomWallpaper.defaultDim)
        #expect(index.chats["7"]?.blur == CustomWallpaper.defaultBlur)
    }
}
