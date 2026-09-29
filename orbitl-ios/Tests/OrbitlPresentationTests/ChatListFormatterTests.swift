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
        #expect(ChatListFormatter.badge(150) == "150")
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

@Suite("Строки списка: типы чатов и детали")
struct ChatListRowTests {
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    let now = Date(timeIntervalSince1970: 1_790_683_200)

    @Test("Компактные счётчики")
    func compact() {
        #expect(ChatListFormatter.compactCount(0) == "0")
        #expect(ChatListFormatter.compactCount(999) == "999")
        #expect(ChatListFormatter.compactCount(1_000) == "1K")
        #expect(ChatListFormatter.compactCount(1_050) == "1K")
        #expect(ChatListFormatter.compactCount(68_349) == "68.3K")
        #expect(ChatListFormatter.compactCount(999_999) == "999K")
        #expect(ChatListFormatter.compactCount(2_500_000) == "2.5M")
    }

    @Test("Группа: автор во второй строке, свои сообщения — «Вы» с галочками")
    func groupSender() {
        var value = chat("g", at: 1_790_672_700, title: "Команда", preview: "Созвон в 5", type: .group)
        value.lastMessage = ChatLastMessage(authorId: "u1", authorName: "Никита")
        var item = formatter.item(for: value, now: now)
        #expect(item.sender == "Никита")
        #expect(item.delivery == nil)
        #expect(item.accessibilityLabel == "Команда, Никита: Созвон в 5, 09:05")

        value.lastMessage = ChatLastMessage(authorId: "me", isOutgoing: true, delivery: .read)
        item = formatter.item(for: value, now: now)
        #expect(item.sender == "Вы")
        #expect(item.delivery == .read)

        value.lastMessage = ChatLastMessage(authorId: "u2")
        #expect(formatter.item(for: value, now: now).sender == nil)
    }

    @Test("Личный чат и канал: без автора, в канале без галочек")
    func privateAndChannel() {
        var dialog = chat("p", at: 1, title: "Аня", type: .private)
        dialog.lastMessage = ChatLastMessage(isOutgoing: true, delivery: .sending)
        dialog.isOnline = true
        let item = formatter.item(for: dialog, now: now)
        #expect(item.sender == nil)
        #expect(item.delivery == .sending)
        #expect(item.isOnline)

        var channel = chat("c", at: 1, title: "Новости", type: .channel)
        channel.lastMessage = ChatLastMessage(isOutgoing: true, delivery: .sent)
        channel.isVerified = true
        channel.isOnline = true
        let channelItem = formatter.item(for: channel, now: now)
        #expect(channelItem.delivery == nil)
        #expect(!channelItem.isOnline)
        #expect(channelItem.accessibilityLabel.hasPrefix("Новости, подтверждённый, канал"))
    }

    @Test("Бот, «Избранное», вложения и фото")
    func special() {
        var bot = chat("b", at: 1, title: "", type: .private)
        bot.isBot = true
        bot.isOnline = true
        let botItem = formatter.item(for: bot, now: now)
        #expect(botItem.title == "Бот")
        #expect(botItem.isBot)
        #expect(!botItem.isOnline)

        var saved = chat(Chat.savedMessagesId, at: 1, title: "", preview: "", type: .private)
        saved.lastMessage = ChatLastMessage(isOutgoing: true, delivery: .sent, media: .photo, thumbnailURL: URL(string: "https://cdn/1.jpg"))
        let savedItem = formatter.item(for: saved, now: now)
        #expect(savedItem.title == "Избранное")
        #expect(savedItem.avatar.kind == .savedMessages)
        #expect(savedItem.preview == "Фотография")
        #expect(savedItem.media == .photo)
        #expect(savedItem.thumbnailURL == URL(string: "https://cdn/1.jpg"))
        #expect(savedItem.delivery == nil)

        var photo = chat("123", at: 1, title: "Иван Петров")
        photo.avatarURL = URL(string: "https://cdn/a.jpg")
        let photoItem = formatter.item(for: photo, now: now)
        #expect(photoItem.avatar.kind == .photo(URL(string: "https://cdn/a.jpg")!, initials: "ИП"))
        #expect(photoItem.avatar.colorIndex == 123 % ChatAvatar.paletteSize)
    }

    @Test("Цвет аватара зависит только от id")
    func avatarColor() {
        #expect(ChatAvatar.colorIndex(for: "7") == 0)
        #expect(ChatAvatar.colorIndex(for: "-8") == 1)
        #expect(ChatAvatar.colorIndex(for: "abc") == ChatAvatar.colorIndex(for: "abc"))
        #expect((0..<ChatAvatar.paletteSize).contains(ChatAvatar.colorIndex(for: "local-xyz")))
        #expect(ChatAvatar.initials(for: "Анна-Мария Ли") == "АМ")
        #expect(ChatAvatar.initials(for: "🙂") == "🙂")
    }

    @Test("Бейджи: без звука, ручная пометка, упоминание, булавка")
    func badgesAndPin() {
        var value = chat("a", at: 1, unread: 68_300)
        value.isMuted = true
        value.pinOrder = 0
        var item = formatter.item(for: value, now: now)
        #expect(item.badge == .count("68.3K"))
        #expect(item.badgeMuted)
        #expect(!item.showsPin)

        value.unreadCount = 0
        value.isMarkedUnread = true
        item = formatter.item(for: value, now: now)
        #expect(item.badge == .dot)
        #expect(item.accessibilityLabel.contains("помечен непрочитанным"))

        value.isMarkedUnread = false
        item = formatter.item(for: value, now: now)
        #expect(item.showsPin)
        #expect(item.accessibilityLabel.contains("закреплён, без звука"))

        value.unreadMentions = 1
        item = formatter.item(for: value, now: now)
        #expect(item.hasMention)
        #expect(!item.showsPin)
    }

    @Test("Набор текста во множественном числе")
    func typingPlural() {
        #expect(ChatListFormatter.typingText(count: 1, type: .group) == "печатает…")
        #expect(ChatListFormatter.typingText(count: 3, type: .private) == "печатает…")
        #expect(ChatListFormatter.typingText(count: 2, type: .group) == "2 участника печатают…")
        #expect(ChatListFormatter.typingText(count: 5, type: .group) == "5 участников печатают…")
        #expect(ChatListFormatter.typingText(count: 21, type: .group) == "21 участник печатает…")
    }
}
