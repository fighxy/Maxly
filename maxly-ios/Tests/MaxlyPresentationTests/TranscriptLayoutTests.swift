import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Раскладка ленты")
struct TranscriptLayoutTests {
    private func message(_ id: String, author: String, name: String = "", at seconds: TimeInterval) -> Message {
        Message(id: id, chatId: "c", authorId: author, text: id, timestamp: Date(timeIntervalSince1970: seconds), status: .sent, authorName: name)
    }

    @Test("Разделитель дня, склейка одного автора, имя над первым и аватар у последнего")
    func rows() {
        let day: TimeInterval = 86_400
        let messages = [
            message("1", author: "bob", name: "Боб", at: 10 * day),
            message("2", author: "bob", name: "Боб", at: 10 * day + 30),
            message("3", author: "me", at: 10 * day + 60),
            message("4", author: "bob", name: "Боб", at: 11 * day),
        ]
        let rows = TranscriptLayout.rows(messages, currentUserId: "me", now: Date(timeIntervalSince1970: 20 * day))
        #expect(rows.map(\.id) == ["1", "2", "3", "4"])
        #expect(rows.map { $0.dayTitle != nil } == [true, false, false, true])
        #expect(rows.map(\.isOutgoing) == [false, false, true, false])
        #expect(rows.map(\.showsAuthorName) == [true, false, false, true])
        #expect(rows.map(\.showsAuthorAvatar) == [false, true, false, true])
        #expect(rows[0].group.joinsNext && rows[1].group.joinsPrevious)
        #expect(!rows[1].group.joinsNext)
    }

    @Test("Модель держит строки и версию состава: правка текста версию не двигает")
    @MainActor
    func viewModelRows() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        repository.emit([message("1", author: "bob", at: 1)])
        #expect(await eventually { model.rows.map(\.id) == ["1"] })
        let version = model.transcriptVersion
        var edited = message("1", author: "bob", at: 1)
        edited.text = "правка"
        repository.emit([edited])
        #expect(await eventually { model.rows.first?.message.text == "правка" })
        #expect(model.transcriptVersion == version)
        repository.emit([edited, message("2", author: "me", at: 2)])
        #expect(await eventually { model.rows.count == 2 })
        #expect(model.transcriptVersion == version + 1)
        model.deactivate()
    }

    @Test("Пауза разрывает серию вместе с именем и аватаром")
    func timeBoundary() {
        let messages = [
            message("1", author: "bob", name: "Боб", at: 43_200),
            message("2", author: "bob", name: "Боб", at: 45_000),
        ]
        let rows = TranscriptLayout.rows(messages, currentUserId: "me")
        #expect(rows.allSatisfy { $0.group == .single && $0.showsAuthorName && $0.showsAuthorAvatar })
    }

    @Test("Новый день разрывает серию одного автора даже без длинной паузы")
    func dayBoundary() {
        let midnight = Calendar.current.startOfDay(for: Date())
        let messages = [
            message("1", author: "bob", name: "Боб", at: midnight.addingTimeInterval(-10).timeIntervalSince1970),
            message("2", author: "bob", name: "Боб", at: midnight.addingTimeInterval(10).timeIntervalSince1970),
        ]
        let rows = TranscriptLayout.rows(messages, currentUserId: "me")
        #expect(rows.allSatisfy { $0.dayTitle != nil && $0.group == .single && $0.showsAuthorName && $0.showsAuthorAvatar })
    }

    @Test("Непрочитанные разрывают склейку с обеих сторон разделителя")
    func unreadBoundary() {
        let messages = (1...3).map { message("\($0)", author: "bob", name: "Боб", at: Double($0)) }
        let rows = TranscriptLayout.rows(messages, currentUserId: "me", unreadAnchorId: "2")
        #expect(rows[0].group == .single)
        #expect(rows[0].showsAuthorAvatar)
        #expect(rows[1].startsUnread && rows[1].showsAuthorName)
        #expect(!rows[1].group.joinsPrevious && rows[1].group.joinsNext)
        #expect(rows[2].group.joinsPrevious && rows[2].showsAuthorAvatar)
    }

    @Test("Закрепление — служебная строка между двумя самостоятельными группами")
    func serviceBoundary() {
        var service = message("2", author: "bob", name: "Боб", at: 2)
        service.content.pin = PinNotice(messageId: "1", preview: "Текст")
        let rows = TranscriptLayout.rows([
            message("1", author: "bob", name: "Боб", at: 1), service,
            message("3", author: "bob", name: "Боб", at: 3),
        ], currentUserId: "me")
        #expect(rows.allSatisfy { $0.group == .single })
        #expect(rows.map(\.showsAuthorName) == [true, false, true])
        #expect(rows.map(\.showsAuthorAvatar) == [true, false, true])
    }

    @Test("Событие чата — тоже служебная строка: без имени и аватара, в непрочитанные не входит")
    func serviceEventBoundary() {
        var event = message("2", author: "bob", name: "Боб", at: 2)
        event.text = ""
        event.content.service = ServiceNotice(event: "leave")
        let messages = [message("1", author: "bob", name: "Боб", at: 1), event, message("3", author: "bob", name: "Боб", at: 3)]
        let rows = TranscriptLayout.rows(messages, currentUserId: "me")
        #expect(rows.allSatisfy { $0.group == .single })
        #expect(rows.map(\.showsAuthorName) == [true, false, true])
        #expect(rows.map(\.showsAuthorAvatar) == [true, false, true])
        // Два непрочитанных — это «1» и «3»: событие не считается.
        #expect(TranscriptLayout.unreadAnchor(messages, unread: 2, currentUserId: "me", complete: true) == "1")
    }

    @Test("Цитата ответа берёт фото исходного сообщения из ленты по id или серверному id")
    func replyMedia() {
        let photo = ChatAttachment.photo(PhotoContent(id: "p1", url: URL(string: "https://example.com/p1.jpg")))
        let original = Message(
            id: "local-1", serverId: "101", chatId: "c", authorId: "bob", text: "",
            timestamp: Date(timeIntervalSince1970: 10), status: .sent,
            content: MessageContent(attachments: [photo])
        )
        func reply(_ id: String, to target: String, kind: MessageReply.Kind) -> Message {
            Message(
                id: id, chatId: "c", authorId: "me", text: "ответ",
                timestamp: Date(timeIntervalSince1970: 20), status: .sent,
                content: MessageContent(reply: MessageReply(messageId: target, authorName: "Боб", preview: "Фото", kind: kind))
            )
        }
        let rows = TranscriptLayout.rows(
            [original, reply("2", to: "101", kind: .photo), reply("3", to: "local-1", kind: .photo), reply("4", to: "999", kind: .text)],
            currentUserId: "me"
        )
        #expect(rows[0].replyMedia == nil)
        #expect(rows[1].replyMedia == photo)
        #expect(rows[2].replyMedia == photo)
        // Исходного сообщения нет в ленте — миниатюры нет.
        #expect(rows[3].replyMedia == nil)
        #expect(TranscriptLayout.repliedMessages([original], currentUserId: "").isEmpty)
    }

    @Test("Автор цитаты берётся из ленты: «Вы» для своего, имя для чужого, без исходного — нет")
    func replyAuthor() {
        func reply(_ id: String, to target: String) -> Message {
            Message(
                id: id, chatId: "c", authorId: "bob", text: "ответ",
                timestamp: Date(timeIntervalSince1970: 30), status: .sent,
                content: MessageContent(reply: MessageReply(messageId: target, authorName: "Сообщение", preview: "текст", kind: .text))
            )
        }
        let mine = Message(id: "local-1", serverId: "101", chatId: "c", authorId: "me", text: "моё",
                           timestamp: Date(timeIntervalSince1970: 10), status: .sent)
        let theirs = message("2", author: "bob", name: " Боб ", at: 20)
        let nameless = message("3", author: "x", at: 21)
        let rows = TranscriptLayout.rows(
            [mine, theirs, nameless, reply("4", to: "101"), reply("5", to: "2"), reply("6", to: "3"), reply("7", to: "999")],
            currentUserId: "me"
        )
        #expect(rows[3].replyAuthor == "Вы")
        #expect(rows[4].replyAuthor == "Боб")
        #expect(rows[5].replyAuthor == nil)
        #expect(rows[6].replyAuthor == nil)
    }

    @Test("Чат с ботом: кнопки только у последнего меню каждого автора, без бота — у всех")
    func latestKeyboardOnly() {
        let keyboard = InlineKeyboard(callbackId: "k", rows: [[InlineButton(type: "CALLBACK", text: "Меню")]])
        func menu(_ id: String, author: String, at seconds: TimeInterval) -> Message {
            Message(id: id, chatId: "c", authorId: author, text: id, timestamp: Date(timeIntervalSince1970: seconds),
                    status: .sent, content: MessageContent(keyboard: keyboard))
        }
        let messages = [
            menu("1", author: "bot", at: 1),
            message("2", author: "me", at: 2),
            menu("3", author: "bot", at: 3),
            message("4", author: "bot", at: 4),
            menu("5", author: "other", at: 5),
        ]
        let bot = TranscriptLayout.rows(messages, currentUserId: "me", latestKeyboardOnly: true)
        #expect(bot.map(\.showsKeyboard) == [false, true, true, true, true])
        let plain = TranscriptLayout.rows(messages, currentUserId: "me")
        #expect(plain.allSatisfy { $0.showsKeyboard })
    }

    @Test("Модель чата с ботом прячет прежние меню и пересчитывает строки, когда узнаёт бота")
    @MainActor
    func botDialogHidesOldMenus() async {
        let keyboard = InlineKeyboard(callbackId: "k", rows: [[InlineButton(type: "CALLBACK", text: "Меню")]])
        func menu(_ id: String, at seconds: TimeInterval) -> Message {
            Message(id: id, chatId: "c", authorId: "bot", text: id, timestamp: Date(timeIntervalSince1970: seconds),
                    status: .sent, content: MessageContent(keyboard: keyboard))
        }
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        repository.emit([menu("1", at: 1), menu("2", at: 2)])
        #expect(await eventually { model.rows.count == 2 })
        #expect(model.rows.allSatisfy { $0.showsKeyboard })
        model.notePeer("bot", isBot: true)
        #expect(model.rows.map(\.showsKeyboard) == [false, true])
    }
}
