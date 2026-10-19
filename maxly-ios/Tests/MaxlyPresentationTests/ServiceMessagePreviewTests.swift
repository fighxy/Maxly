import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Список чатов: служебное событие последним")
struct ServiceMessagePreviewTests {
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    let now = Date(timeIntervalSince1970: 1_790_683_200)

    private func chat(type: ChatType = .group, preview: String?, outgoing: Bool = false) -> Chat {
        Chat(
            id: "g1",
            title: "Дача",
            type: type,
            lastMessageId: "m1",
            updatedAt: now.addingTimeInterval(-600),
            preview: preview,
            lastMessage: ChatLastMessage(authorId: "u1", authorName: "Анна", isOutgoing: outgoing, delivery: outgoing ? .read : nil, media: .service)
        )
    }

    @Test("Текст события без имени автора над ним и без галочек")
    func groupRow() {
        let item = formatter.item(for: chat(preview: "Анна изменил(а) название на «Дача 2027»"), now: now)
        #expect(item.preview == "Анна изменил(а) название на «Дача 2027»")
        #expect(item.sender == nil)
        let own = formatter.item(for: chat(preview: "Вы покинули чат", outgoing: true), now: now)
        #expect(own.sender == nil)
        #expect(own.delivery == nil)
    }

    @Test("Без текста — «Служебное сообщение», а не «Вложение»")
    func withoutText() {
        #expect(formatter.item(for: chat(preview: nil), now: now).preview == "Служебное сообщение")
        #expect(formatter.preview(for: chat(type: .private, preview: nil)) == "Служебное сообщение")
    }

    @Test("Личный чат: «теперь в MAX»")
    func joined() {
        let item = formatter.item(for: chat(type: .private, preview: "Анна теперь в MAX"), now: now)
        #expect(item.preview == "Анна теперь в MAX")
        #expect(item.sender == nil)
    }
}
