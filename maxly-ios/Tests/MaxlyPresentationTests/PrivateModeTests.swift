import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Приватный режим: настройки")
@MainActor
struct PrivateModeSettingsTests {
    @Test("По умолчанию выключен, показывает всё, кнопка в списке есть")
    func defaults() {
        let settings = PrivateModeSettings(store: InMemoryPrivateModeStore())
        #expect(!settings.isEnabled)
        #expect(settings.style == .placeholder)
        #expect(settings.showsQuickToggle)
        #expect(settings.display == .visible)
        #expect(!settings.display.isMasked)
    }

    @Test("Включение, вид и кнопка сохраняются; то же значение не пишется")
    func saves() {
        let store = InMemoryPrivateModeStore()
        let settings = PrivateModeSettings(store: store)
        settings.setEnabled(true)
        #expect(settings.display == .placeholder)
        #expect(store.saved == PrivateModePreferences(isEnabled: true))
        settings.setStyle(.blur)
        #expect(settings.display == .blur)
        settings.setShowsQuickToggle(false)
        #expect(store.saveCount == 3)
        settings.setEnabled(true)
        settings.setStyle(.blur)
        settings.setShowsQuickToggle(false)
        #expect(store.saveCount == 3)
        let again = PrivateModeSettings(store: store)
        #expect(again.preferences == PrivateModePreferences(isEnabled: true, style: .blur, showsQuickToggle: false))
    }

    @Test("Быстрое переключение туда и обратно")
    func toggle() {
        let settings = PrivateModeSettings(store: InMemoryPrivateModeStore())
        settings.toggle()
        #expect(settings.isEnabled)
        settings.toggle()
        #expect(!settings.isEnabled)
        #expect(settings.display == .visible)
    }

    @Test("Выключенный режим показывает всё при любом виде")
    func displayFollowsEnabled() {
        #expect(PrivateModeDisplay(PrivateModePreferences(isEnabled: false, style: .blur)) == .visible)
        #expect(PrivateModeDisplay(PrivateModePreferences(isEnabled: true, style: .blur)) == .blur)
        #expect(PrivateModeDisplay(PrivateModePreferences(isEnabled: true, style: .placeholder)) == .placeholder)
    }
}

@Suite("Приватный режим: строки списка")
struct PrivateModeListTests {
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    /// Вторник, 29 сентября 2026, 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_790_683_200)

    private func chat(
        _ id: String,
        title: String = "Аня Петрова",
        type: ChatType = .private,
        preview: String? = "Встречаемся в 7 у метро",
        last: ChatLastMessage? = ChatLastMessage(authorName: "Аня", isOutgoing: false)
    ) -> Chat {
        Chat(
            id: id,
            title: title,
            type: type,
            lastMessageId: preview == nil ? nil : "m1",
            unreadCount: 3,
            updatedAt: now.addingTimeInterval(-600),
            preview: preview,
            lastMessage: last,
            avatarURL: URL(string: "https://cdn.test/a.jpg"),
            pinOrder: 1,
            isMuted: true,
            isVerified: true,
            isOnline: true,
            unreadMentions: 1
        )
    }

    @Test("Личный чат: общее название, круг того же цвета без фото, «Вы получили сообщение»")
    func privateChat() {
        let item = formatter.item(for: chat("42"), now: now)
        let masked = PrivateModeMask.item(item)
        #expect(masked.id == "42")
        #expect(masked.title == "Личный чат")
        #expect(masked.avatar == ChatAvatar(kind: .initials(""), colorIndex: item.avatar.colorIndex))
        #expect(masked.preview == "Вы получили сообщение")
        #expect(masked.sender == nil)
        #expect(!masked.isOnline)
        #expect(!masked.isVerified)
        #expect(masked.thumbnailURL == nil)
        #expect(masked.media == nil)
        // Служебное остаётся: время, бейджи, закреп, «без звука».
        #expect(masked.time == item.time)
        #expect(masked.badge == item.badge)
        #expect(masked.unreadCount == 3)
        #expect(masked.hasMention)
        #expect(masked.isPinned)
        #expect(masked.isMuted)
        #expect(!masked.accessibilityLabel.contains("Аня"))
        #expect(!masked.accessibilityLabel.contains("метро"))
        #expect(masked.accessibilityLabel.hasPrefix("Личный чат"))
    }

    @Test("Группа со своим последним сообщением: без автора, «Вы отправили сообщение», галочки остаются")
    func groupOutgoing() {
        let last = ChatLastMessage(authorName: "Я", isOutgoing: true, delivery: .read, media: .photo,
                                   thumbnailURL: URL(string: "https://cdn.test/t.jpg"), isForwarded: true)
        let item = formatter.item(for: chat("7", title: "Дача 2026", type: .group, preview: "фото с дачи", last: last), now: now)
        #expect(item.sender == "Вы")
        #expect(item.lastIsOutgoing)
        let masked = PrivateModeMask.item(item)
        #expect(masked.title == "Групповой чат")
        #expect(masked.preview == "Вы отправили сообщение")
        #expect(masked.sender == nil)
        #expect(masked.delivery == .read)
        #expect(!masked.isForwarded)
        #expect(masked.thumbnailURL == nil)
    }

    @Test("Канал, бот и «Избранное»")
    func kinds() {
        let channel = PrivateModeMask.item(formatter.item(for: chat("1", title: "Новости", type: .channel), now: now))
        #expect(channel.title == "Канал")
        var botChat = chat("2", title: "Погода")
        botChat.isBot = true
        let bot = PrivateModeMask.item(formatter.item(for: botChat, now: now))
        #expect(bot.title == "Личный чат")
        #expect(!bot.isBot)
        let saved = PrivateModeMask.item(formatter.item(for: chat(Chat.savedMessagesId, title: ""), now: now))
        #expect(saved.title == "Избранное")
        #expect(saved.avatar.kind == .savedMessages)
    }

    @Test("Черновик скрыт, «печатает…» и пустой чат остаются как есть")
    func styles() {
        var drafted = chat("3")
        drafted.draft = ChatDraft(text: "Секретный план", updatedAt: now)
        let draft = PrivateModeMask.item(formatter.item(for: drafted, now: now))
        #expect(draft.previewStyle == .draft)
        #expect(draft.preview == "скрыт")
        #expect(!draft.accessibilityLabel.contains("Секретный"))

        let named = [TypingFormatter.Participant(name: "Аня"), TypingFormatter.Participant(name: "Боря")]
        let typing = PrivateModeMask.item(formatter.item(for: chat("4", type: .group), now: now, typing: named))
        #expect(typing.previewStyle == .typing)
        // Имена печатающих приватный режим прячет: остаётся счёт.
        #expect(typing.preview == "2 участника печатают…")
        #expect(!typing.accessibilityLabel.contains("Аня"))

        let empty = PrivateModeMask.item(formatter.item(for: chat("5", preview: nil, last: nil), now: now))
        #expect(empty.previewStyle == .empty)
        #expect(empty.preview == "Нет сообщений")
    }

    @Test("Строка архива без названия и текста свежего чата")
    func archive() {
        let summary = ChatArchiveSummary(count: 4, unreadCount: 2, title: "Бухгалтерия", preview: "Счёт до пятницы")
        let masked = PrivateModeMask.archive(summary)
        #expect(masked.count == 4)
        #expect(masked.unreadCount == 2)
        #expect(masked.title == "Скрытый чат")
        #expect(masked.preview == "Сообщение скрыто")
    }

    @Test("Заголовки по типу и для звонков")
    func titles() {
        #expect(PrivateModeMask.chatTitle(type: .private) == "Личный чат")
        #expect(PrivateModeMask.chatTitle(type: .group) == "Групповой чат")
        #expect(PrivateModeMask.chatTitle(type: .channel) == "Канал")
        #expect(PrivateModeMask.chatTitle(type: .private, isSavedMessages: true) == "Избранное")
        #expect(PrivateModeMask.callTitle(isGroup: false) == "Звонок")
        #expect(PrivateModeMask.callTitle(isGroup: true) == "Групповой звонок")
    }

    @Test("Значки архива и «Избранного» не превращаются в круги")
    func specialAvatars() {
        let archive = ChatAvatar(kind: .archive, colorIndex: 0)
        #expect(PrivateModeMask.avatar(archive) == archive)
        let photo = ChatAvatar(kind: .photo(URL(string: "https://cdn.test/p.jpg")!, initials: "АП"), colorIndex: 5)
        #expect(PrivateModeMask.avatar(photo) == ChatAvatar(kind: .initials(""), colorIndex: 5))
    }
}

@Suite("Приватный режим: сообщения")
struct PrivateModeMessageTests {
    private let content = MessageContent(
        reply: MessageReply(messageId: "9", authorName: "Боря", preview: "Где ключи?", kind: .text),
        attachments: [.photo(PhotoContent(id: "p1", url: URL(string: "https://cdn.test/p.jpg")))],
        reactions: [MessageReaction(emoji: "👍", count: 2, mine: true)],
        comments: CommentSummary(count: 4),
        formatting: [TextSpan(kind: .strong, from: 0, length: 3)],
        forward: MessageForward(authorName: "Канал новостей", text: "Срочно"),
        edited: true
    )

    private func message(outgoing: Bool) -> Message {
        Message(
            id: "local-1",
            serverId: "501",
            chatId: "7",
            authorId: outgoing ? "me" : "15",
            text: "Код от подъезда 1234",
            timestamp: Date(timeIntervalSince1970: 1_790_680_000),
            status: .sent,
            mediaId: "p1",
            content: content,
            authorName: "Аня",
            authorAvatarURL: URL(string: "https://cdn.test/a.jpg")
        )
    }

    @Test("Входящее: общая подпись, без вложений, реакций, цитаты, пересылки и автора")
    func incoming() {
        let original = message(outgoing: false)
        let masked = PrivateModeMask.message(original, outgoing: false)
        #expect(masked.text == "Вы получили сообщение")
        #expect(masked.displayText == "Вы получили сообщение")
        #expect(masked.content == .empty)
        #expect(masked.authorName.isEmpty)
        #expect(masked.authorAvatarURL == nil)
        #expect(masked.mediaId == nil)
        // Для ленты остаётся то, по чему она устроена: id, автор (склейка пузырей), время, статус.
        #expect(masked.id == original.id)
        #expect(masked.serverId == "501")
        #expect(masked.authorId == "15")
        #expect(masked.timestamp == original.timestamp)
        #expect(masked.status == .sent)
    }

    @Test("Своё: «Вы отправили сообщение», статус не теряется")
    func outgoing() {
        var original = message(outgoing: true)
        original.status = .failed
        let masked = PrivateModeMask.message(original, outgoing: true)
        #expect(masked.text == "Вы отправили сообщение")
        #expect(masked.status == .failed)
        #expect(masked.replySnippet == "Вы отправили сообщение")
    }
}

@Suite("Приватный режим: открытие касанием")
@MainActor
struct PrivateModeRevealTests {
    @Test("Касание открывает, повторное прячет")
    func toggle() {
        let reveal = PrivateModeReveal(sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        #expect(!reveal.isRevealed("a"))
        reveal.toggle("a")
        #expect(reveal.isRevealed("a"))
        #expect(!reveal.isRevealed("b"))
        reveal.toggle("a")
        #expect(!reveal.isRevealed("a"))
    }

    @Test("Открытое прячется само по таймеру")
    func autoHide() async throws {
        let reveal = PrivateModeReveal(duration: .milliseconds(20), sleep: { try await Task.sleep(for: $0) })
        reveal.reveal("a")
        #expect(reveal.isRevealed("a"))
        for _ in 0..<100 where reveal.isRevealed("a") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!reveal.isRevealed("a"))
    }

    @Test("Спрятанное вручную старый таймер не трогает; «спрятать все» отменяет таймеры")
    func hideAll() async throws {
        let reveal = PrivateModeReveal(duration: .milliseconds(30), sleep: { try await Task.sleep(for: $0) })
        reveal.reveal("a")
        reveal.reveal("b")
        reveal.hideAll()
        #expect(reveal.revealed.isEmpty)
        // Открыли снова: прежний (отменённый) таймер не должен спрятать его раньше срока.
        reveal.reveal("a")
        #expect(reveal.isRevealed("a"))
        reveal.hide("a")
        #expect(!reveal.isRevealed("a"))
    }

    @Test("Повторное открытие продлевает срок")
    func extend() async throws {
        // Первый сон отменяется повторным открытием и падает; второй ждёт долго.
        let reveal = PrivateModeReveal(duration: .seconds(60), sleep: { try await Task.sleep(for: $0) })
        reveal.reveal("a")
        reveal.reveal("a")
        try await Task.sleep(for: .milliseconds(20))
        #expect(reveal.isRevealed("a"))
    }
}
