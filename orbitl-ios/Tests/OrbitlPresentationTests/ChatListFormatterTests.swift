import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlPresentation

@Suite("Тексты списка чатов")
struct ChatListFormatterTests {
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))

    /// Вторник, 29 сентября 2026, 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_790_683_200)

    func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    @Test("Сегодня часы, вчера «вчера», на неделе день, в году число, раньше дата")
    func timeLabels() {
        #expect(formatter.timeLabel(for: date("2026-09-29T09:05:00Z"), now: now) == "09:05")
        #expect(formatter.timeLabel(for: date("2026-09-29T00:00:00Z"), now: now) == "00:00")
        #expect(formatter.timeLabel(for: date("2026-09-28T23:59:00Z"), now: now) == "вчера")
        #expect(formatter.timeLabel(for: date("2026-09-27T10:00:00Z"), now: now) == "вс")
        #expect(formatter.timeLabel(for: date("2026-09-23T10:00:00Z"), now: now) == "ср")
        #expect(formatter.timeLabel(for: date("2026-09-22T10:00:00Z"), now: now) == "22 сен")
        #expect(formatter.timeLabel(for: date("2026-01-05T10:00:00Z"), now: now) == "5 янв")
        #expect(formatter.timeLabel(for: date("2025-12-31T10:00:00Z"), now: now) == "31.12.2025")
        #expect(formatter.timeLabel(for: date("2026-10-01T10:00:00Z"), now: now) == "01.10.2026")
        #expect(formatter.timeLabel(for: Date(timeIntervalSince1970: 0), now: now) == "")
    }

    @Test("Часовой пояс календаря решает, что считать сегодня")
    func timeZone() {
        let novosibirsk = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "Asia/Novosibirsk")!))
        // 20:00 UTC 28 сентября — это уже 03:00 29 сентября в Новосибирске.
        #expect(novosibirsk.timeLabel(for: date("2026-09-28T20:00:00Z"), now: now) == "03:00")
        #expect(formatter.timeLabel(for: date("2026-09-28T20:00:00Z"), now: now) == "вчера")
    }

    @Test("Превью в одну строку, вложение и пустой чат")
    func previews() {
        #expect(formatter.preview(for: chat("1", at: 1, preview: "Первая\n\n  вторая ")) == "Первая вторая")
        #expect(formatter.preview(for: chat("1", at: 1, preview: nil)) == "Нет сообщений")
        var media = chat("1", at: 1, preview: "")
        media.lastMessageId = "m1"
        #expect(formatter.preview(for: media) == "Вложение")
    }

    @Test("Пустой заголовок заменяется типом чата")
    func titles() {
        #expect(formatter.title(for: chat("1", at: 1, title: "  ", type: .private)) == "Личный чат")
        #expect(formatter.title(for: chat("1", at: 1, title: "", type: .group)) == "Группа")
        #expect(formatter.title(for: chat("1", at: 1, title: "", type: .channel)) == "Канал")
        #expect(formatter.title(for: chat("1", at: 1, title: " Аня ")) == "Аня")
    }

    @Test("Бейдж и фраза для VoiceOver")
    func badges() {
        #expect(ChatListFormatter.badge(0) == nil)
        #expect(ChatListFormatter.badge(-1) == nil)
        #expect(ChatListFormatter.badge(7) == "7")
        #expect(ChatListFormatter.badge(99) == "99")
        #expect(ChatListFormatter.badge(150) == "99+")
        #expect(ChatListFormatter.unreadPhrase(1) == "1 непрочитанное сообщение")
        #expect(ChatListFormatter.unreadPhrase(3) == "3 непрочитанных сообщения")
        #expect(ChatListFormatter.unreadPhrase(5) == "5 непрочитанных сообщений")
        #expect(ChatListFormatter.unreadPhrase(11) == "11 непрочитанных сообщений")
        #expect(ChatListFormatter.unreadPhrase(21) == "21 непрочитанное сообщение")
        #expect(ChatListFormatter.unreadPhrase(112) == "112 непрочитанных сообщений")
    }

    @Test("Строка списка собирает всё вместе")
    func item() {
        let item = formatter.item(for: chat("c", at: 1_790_672_700, unread: 2, title: "Команда", preview: "Созвон"), now: now)
        #expect(item.id == "c")
        #expect(item.title == "Команда")
        #expect(item.preview == "Созвон")
        #expect(item.time == "09:05")
        #expect(item.unreadBadge == "2")
        #expect(item.accessibilityLabel == "Команда, Созвон, 09:05, 2 непрочитанных сообщения")
    }
}
