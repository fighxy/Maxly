import Foundation
import Testing
@testable import MaxlyDomain

@Suite("Свои обои: выбор и формат")
struct CustomWallpaperTests {
    @Test("Фото чата, затем «Без обоев» чата, затем общее фото, иначе встроенные")
    func resolution() {
        let chat = CustomWallpaperIndex.chatKey(account: "7", chatId: "1")
        let other = CustomWallpaperIndex.chatKey(account: "7", chatId: "2")
        var index = CustomWallpaperIndex()
        #expect(index.resolve(chatKey: chat) == .preset)
        #expect(index.resolve(chatKey: nil) == .preset)
        index.global = "global-a.jpg"
        #expect(index.resolve(chatKey: chat) == .photo("global-a.jpg"))
        #expect(index.resolve(chatKey: nil) == .photo("global-a.jpg"))
        index.chats[chat] = CustomWallpaperIndex.plainValue
        #expect(index.choice(chatKey: chat) == .plain)
        #expect(index.resolve(chatKey: chat) == .plain)
        index.chats[chat] = "chat-b.jpg"
        #expect(index.choice(chatKey: chat) == .photo("chat-b.jpg"))
        #expect(index.resolve(chatKey: chat) == .photo("chat-b.jpg"))
        #expect(index.choice(chatKey: other) == .global)
        #expect(index.resolve(chatKey: other) == .photo("global-a.jpg"))
        index.global = nil
        #expect(index.resolve(chatKey: other) == .preset)
        #expect(index.photoFiles == ["chat-b.jpg"])
    }

    @Test("Ключ чата — аккаунт и чат: у другого аккаунта свои обои")
    func accountKey() {
        #expect(CustomWallpaperIndex.chatKey(account: "7", chatId: "-100") == "7.-100")
        var index = CustomWallpaperIndex()
        index.chats[CustomWallpaperIndex.chatKey(account: "7", chatId: "1")] = "plain"
        #expect(index.choice(chatKey: CustomWallpaperIndex.chatKey(account: "8", chatId: "1")) == .global)
    }

    @Test("Затемнение 0–60 %, копия до 2560 пикселей по длинной стороне без растяжения")
    func style() {
        #expect(CustomWallpaperStyle.clampDim(-5) == 0)
        #expect(CustomWallpaperStyle.clampDim(80) == 60)
        #expect(CustomWallpaperStyle.dimOpacity(30) == 0.3)
        #expect(CustomWallpaperStyle.dimCaption(25) == "Затемнение — 25\u{00A0}%")
        #expect(CustomWallpaperStyle.target(width: 4032, height: 3024) == (2560, 1920))
        #expect(CustomWallpaperStyle.target(width: 3000, height: 6000) == (1280, 2560))
        #expect(CustomWallpaperStyle.target(width: 800, height: 600) == (800, 600))
        #expect(CustomWallpaperStyle.blurredName("chat-a.jpg") == "blur-chat-a.jpg")
    }

    @Test("Список в JSON: global, dimPercent, blur, chats; незнакомые и пустые поля — по умолчанию")
    func json() throws {
        let index = CustomWallpaperIndex(global: "global-a.jpg", dimPercent: 20, blur: true, chats: ["7.-42": "chat-b.jpg", "7.5": "plain"])
        let data = try JSONEncoder().encode(index)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["global"] as? String == "global-a.jpg")
        #expect(object["dimPercent"] as? Int == 20)
        #expect(object["blur"] as? Bool == true)
        #expect((object["chats"] as? [String: String])?["7.5"] == "plain")
        #expect(try JSONDecoder().decode(CustomWallpaperIndex.self, from: data) == index)

        let old = #"{"global":"","dimPercent":99,"chats":{"7.1":"chat-c.jpg"}}"#
        let lenient = try JSONDecoder().decode(CustomWallpaperIndex.self, from: Data(old.utf8))
        #expect(lenient.global == nil)
        #expect(lenient.dimPercent == 60)
        #expect(lenient.blur == false)
        #expect(lenient.chats == ["7.1": "chat-c.jpg"])
    }
}
