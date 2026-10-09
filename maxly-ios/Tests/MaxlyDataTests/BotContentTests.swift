import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Превью ссылок и кнопки ботов в сообщении")
struct BotContentTests {
    @Test("SHARE становится превью ссылки, картинка — из PHOTO внутри")
    func linkPreview() throws {
        let json = """
        {"attaches":[{"_type":"SHARE","shareId":5,"url":"https://www.example.org/post","host":"www.example.org",
        "title":"Заголовок","description":" Описание ","image":{"_type":"PHOTO","baseUrl":"https://i.example/1.jpg","width":1200,"height":600}}]}
        """
        let content = MessageContentCodec.decode(json)
        let preview = try #require(content.linkPreview)
        #expect(preview.url == "https://www.example.org/post")
        #expect(preview.site == "example.org")
        #expect(preview.title == "Заголовок")
        #expect(preview.summary == "Описание")
        #expect(preview.imageURL == URL(string: "https://i.example/1.jpg"))
        #expect(preview.imageWidth == 1200)
        #expect(content.attachments.isEmpty)
        // Запись базы сохраняет превью.
        #expect(MessageContentCodec.decode(MessageContentCodec.encode(content)).linkPreview == preview)
    }

    @Test("INLINE_KEYBOARD: ряды, типы и callbackId; пустые кнопки и ряды отбрасываются")
    func keyboard() throws {
        let json = """
        {"attaches":[{"_type":"INLINE_KEYBOARD","callbackId":"cb-1","keyboard":{"buttons":[
        [{"type":"callback","text":"Да","payload":"yes"},{"type":"CALLBACK","text":"Нет","payload":"no"}],
        [{"type":"LINK","text":"Сайт","url":"https://max.ru"}],
        [{"type":"OPEN_APP","text":"Приложение","contactId":77,"webApp":"https://max.ru/bot?startapp=promo"}],
        [{"type":"CALLBACK","text":"  "}]
        ]}}]}
        """
        let keyboard = try #require(MessageContentCodec.decode(json).keyboard)
        #expect(keyboard.callbackId == "cb-1")
        #expect(keyboard.rows.map { $0.map(\.text) } == [["Да", "Нет"], ["Сайт"], ["Приложение"]])
        #expect(keyboard.rows[0][0].type == "CALLBACK")
        #expect(keyboard.rows[0][0].action == .callback)
        #expect(keyboard.rows[1][0].action == .link(URL(string: "https://max.ru")!))
        #expect(keyboard.rows[2][0].action == .openApp(botId: "77", startParam: "promo"))
    }

    @Test("Сообщение без SHARE и клавиатуры их не получает")
    func none() {
        let content = MessageContentCodec.decode(#"{"attaches":[{"_type":"PHOTO","baseUrl":"https://x/1.jpg"}]}"#)
        #expect(content.linkPreview == nil)
        #expect(content.keyboard == nil)
    }
}
