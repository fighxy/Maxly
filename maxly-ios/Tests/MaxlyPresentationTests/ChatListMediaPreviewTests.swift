import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Список чатов: вложение вместо текста")
struct ChatListMediaPreviewTests {
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    let now = Date(timeIntervalSince1970: 1_790_683_200)

    private func chat(type: ChatType = .group, preview: String? = nil, media: MessageMediaKind?, author: String = "Юлия") -> Chat {
        Chat(
            id: "g1",
            title: "Красная Сибирь 120А",
            type: type,
            lastMessageId: "m1",
            updatedAt: now.addingTimeInterval(-600),
            preview: preview,
            lastMessage: ChatLastMessage(authorId: "u1", authorName: author, isOutgoing: false, media: media)
        )
    }

    @Test("Каждый вид вложения без текста подписан словом")
    func labels() {
        let expected: [MessageMediaKind: String] = [
            .photo: "Фотография", .video: "Видео", .voice: "Голосовое сообщение",
            .videoMessage: "Видеосообщение", .audio: "Аудио", .file: "Файл", .sticker: "Стикер",
            .gif: "GIF", .location: "Геопозиция", .contact: "Контакт", .poll: "Опрос",
            .call: "Звонок", .groupCall: "Групповой звонок",
        ]
        #expect(Set(expected.keys) == Set(MessageMediaKind.allCases))
        for (kind, label) in expected {
            #expect(formatter.item(for: chat(media: kind), now: now).preview == label)
        }
    }

    @Test("Группа: имя автора отдельно, под ним «Голосовое сообщение»")
    func groupSender() {
        let item = formatter.item(for: chat(media: .voice), now: now)
        #expect(item.sender == "Юлия")
        #expect(item.preview == "Голосовое сообщение")
        #expect(item.media == .voice)
    }

    @Test("Фото с подписью — подпись; без подписи и пустой строкой — «Фотография»")
    func captionWins() {
        #expect(formatter.item(for: chat(preview: "Переоценка бумага", media: .photo), now: now).preview == "Переоценка бумага")
        #expect(formatter.item(for: chat(preview: "", media: .photo), now: now).preview == "Фотография")
        #expect(formatter.item(for: chat(preview: "  ", media: .photo), now: now).preview == "Фотография")
    }

    @Test("Личный чат: без имени автора")
    func privateChat() {
        let item = formatter.item(for: chat(type: .private, media: .photo), now: now)
        #expect(item.sender == nil)
        #expect(item.preview == "Фотография")
    }

    @Test("Приватный режим: вид вложения не выдаётся")
    func masked() {
        let masked = PrivateModeMask.item(formatter.item(for: chat(media: .photo), now: now))
        #expect(masked.preview == "Вы получили сообщение")
        #expect(masked.sender == nil)
        #expect(masked.media == nil)
    }
}
