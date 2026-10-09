import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Строка чата: вложение последнего сообщения и комментарии канала")
struct ChatPreviewMediaTests {
    @Test("Вид вложения, обложка и флаг комментариев из ядра доходят до чата")
    func fromCore() {
        let record = CoreMapping.chat(CoreChat(
            id: "7", title: "Канал", type: "CHANNEL", lastMessageId: "1", lastText: "", updatedAtMs: 1_000, unread: 0,
            lastMedia: "voice", lastThumbURL: "", comments: 0
        ))
        #expect(record.lastMedia == .voice)
        #expect(record.lastThumbnailURL == nil)
        #expect(record.commentsEnabled == false)
        #expect(record.domain.lastMessage?.media == .voice)
        #expect(record.domain.commentsEnabled == false)

        let photo = CoreMapping.chat(CoreChat(
            id: "8", title: "", type: "DIALOG", lastMessageId: "2", lastText: "", updatedAtMs: 1_000, unread: 0,
            lastMedia: "photo", lastThumbURL: "https://i.example/p", comments: -1
        ))
        #expect(photo.lastMedia == .photo)
        #expect(photo.lastThumbnailURL == URL(string: "https://i.example/p"))
        #expect(photo.commentsEnabled == nil)

        let text = CoreMapping.chat(CoreChat(
            id: "9", title: "", type: "DIALOG", lastMessageId: "3", lastText: "привет", updatedAtMs: 1_000, unread: 0
        ))
        #expect(text.lastMedia == nil)
        #expect(text.domain.lastMessage == nil)
    }

    @Test("Пуш с вложением называет его для строки списка")
    func fromPush() {
        let voice = MessageContentCodec.decode(#"{"attaches":[{"_type":"AUDIO","audioId":3,"url":"https://a.example/a.ogg"}]}"#)
        #expect(voice.previewMedia == .voice)
        let round = MessageContentCodec.decode(#"{"attaches":[{"_type":"VIDEO","videoId":4,"videoType":1,"thumbnail":"https://v.example/t.jpg"}]}"#)
        #expect(round.previewMedia == .videoMessage)
        #expect(round.previewThumbnail == URL(string: "https://v.example/t.jpg"))
        let photo = MessageContentCodec.decode(#"{"attaches":[{"_type":"PHOTO","photoId":5,"baseUrl":"https://i.example/5"}]}"#)
        #expect(photo.previewMedia == .photo)
        #expect(photo.previewThumbnail == URL(string: "https://i.example/5"))
        #expect(MessageContent.empty.previewMedia == nil)
    }
}
