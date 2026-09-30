import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Фрагмент сообщения")
struct MessageContentCodecTests {
    @Test("Пустой и битый JSON не выдумывают контент, пустой фрагмент не пишется")
    func emptyAndInvalid() {
        #expect(MessageContentCodec.decode("") == .empty)
        #expect(MessageContentCodec.decode("   ") == .empty)
        #expect(MessageContentCodec.decode("нет") == .empty)
        #expect(MessageContentCodec.decode("[]") == .empty)
        #expect(MessageContentCodec.encode(.empty) == "")
    }

    @Test("Серверный JSON: цитата, фото, видео, голос, реакции и счётчик")
    func serverPayload() throws {
        let content = MessageContentCodec.decode(serverJSON)
        let reply = try #require(content.reply)
        #expect(reply.messageId == "parent-1")
        #expect(reply.authorName == "Анна")
        #expect(reply.preview == "Исходное")
        #expect(reply.kind == .text)

        let photo = try #require(content.visuals.first?.photo)
        #expect(photo.id == "15")
        #expect(photo.url == URL(string: "https://cdn.example/p.jpg"))
        #expect(photo.width == 800)
        #expect(photo.height == 600)

        let video = try #require(content.attachments.compactMap(\.video).first)
        #expect(video.id == "v1")
        #expect(video.durationMs == 3200)
        #expect(video.isRound)
        #expect(video.posterURL == URL(string: "https://cdn.example/t.jpg"))

        let voice = try #require(content.voices.first)
        #expect(voice.id == "a1")
        #expect(voice.durationMs == 3200)
        #expect(voice.waveform == [10, 200, 40])

        #expect(content.reactions == [
            MessageReaction(emoji: "❤️", count: 2, mine: true),
            MessageReaction(emoji: "👍", count: 1, mine: false),
        ])
        #expect(content.comments?.count == 5)
        #expect(content.threadOf == nil)
        #expect(!content.isEmpty)
    }

    @Test("Фото, голос и файл читаются вместе, токен адресом не становится")
    func photoVoiceAndFile() throws {
        let content = MessageContentCodec.decode(#"""
        {"attaches":[
          {"_type":"PHOTO","photoId":15,"baseUrl":"https://cdn.example/p.jpg","width":800,"height":600},
          {"_type":"AUDIO","audioId":3,"url":"https://cdn.example/a.ogg","duration":3200,"wave":[10,200]},
          {"_type":"FILE","fileId":9,"name":"отчёт.pdf","size":2048,"baseUrl":"https://cdn.example/f.pdf"},
          {"_type":"FILE","fileId":10,"name":"секрет.bin","size":4,"token":"ft"}
        ]}
        """#)
        let photo = try #require(content.visuals.first?.photo)
        #expect(photo.url == URL(string: "https://cdn.example/p.jpg"))
        let voice = try #require(content.voices.first)
        #expect(voice.url == URL(string: "https://cdn.example/a.ogg"))
        #expect(voice.durationMs == 3200)
        #expect(voice.waveform == [10, 200])
        #expect(content.files.count == 2)
        #expect(content.files[0].name == "отчёт.pdf")
        #expect(content.files[0].size == 2048)
        #expect(content.files[0].url == URL(string: "https://cdn.example/f.pdf"))
        #expect(content.files[1].name == "секрет.bin")
        #expect(content.files[1].url == nil)

        let reply = MessageContentCodec.decode(#"""
        {"link":{"message":{"id":"f","text":"","attaches":[{"_type":"FILE","fileId":1,"name":"отчёт.pdf"}]}}}
        """#)
        let quote = try #require(reply.reply)
        #expect(quote.kind == .file)
        #expect(quote.preview == "отчёт.pdf")
    }

    @Test("Пересылка не становится цитатой, нулевой счётчик комментариев остаётся")
    func forwardAndZeroComments() {
        let forwarded = MessageContentCodec.decode(#"""
        {"link":{"type":"FORWARD","messageId":"x","message":{"id":"x","text":"чужое"}}}
        """#)
        #expect(forwarded.reply == nil)

        let commented = MessageContentCodec.decode(#"{"commentsCount":0}"#)
        #expect(commented.comments?.count == 0)
        #expect(!commented.isEmpty)
    }

    @Test("Дорожка из base64 и цитата без текста берут вид вложения")
    func waveAndVoiceReply() throws {
        let voiced = MessageContentCodec.decode(#"""
        {"attaches":[{"type":"AUDIO","audioId":"a","wave":"AQIDBAUGBwgJ"}]}
        """#)
        #expect(voiced.voices.first?.waveform == [1, 2, 3, 4, 5, 6, 7, 8, 9])

        let reply = MessageContentCodec.decode(#"""
        {"link":{"message":{"id":"v","text":"","attaches":[{"_type":"AUDIO","audioId":"a"}]}}}
        """#)
        let quote = try #require(reply.reply)
        #expect(quote.kind == .voice)
        #expect(quote.preview == "Голосовое сообщение")
        #expect(quote.authorName == "Сообщение")
    }

    @Test("Каноническая запись читается обратно, включая тред")
    func canonicalRoundTrip() {
        let content = MessageContent(
            reply: MessageReply(messageId: "p", authorName: "Анна", preview: "Исходное", kind: .text),
            attachments: [
                .voice(VoiceContent(
                    id: "a1",
                    url: URL(string: "https://cdn.example/a.ogg"),
                    waveform: [1, 2],
                    durationMs: 3200
                )),
            ],
            reactions: [MessageReaction(emoji: "❤️", count: 2, mine: true)],
            comments: CommentSummary(count: 5),
            threadOf: "post-1"
        )
        let encoded = MessageContentCodec.encode(content)
        #expect(!encoded.isEmpty)
        #expect(MessageContentCodec.decode(encoded) == content)
        #expect(MessageContentCodec.encode(MessageContentCodec.decode(encoded)) == encoded)
    }

    private var serverJSON: String {
        #"""
        {
          "link": {"type": "REPLY", "message": {"id": "parent-1", "text": "Исходное", "senderName": "Анна"}},
          "attaches": [
            {"_type": "PHOTO", "photoId": 15, "baseUrl": "https://cdn.example/p.jpg", "width": 800, "height": 600},
            {"_type": "VIDEO", "videoId": "v1", "duration": 3200, "videoType": 1, "thumbnail": "https://cdn.example/t.jpg"},
            {"_type": "AUDIO", "audioId": "a1", "duration": 3200, "wave": [10, 200, 40]}
          ],
          "reactionInfo": {
            "yourReaction": "❤️",
            "counters": [
              {"reaction": "❤️", "count": 2},
              {"reaction": "👍", "count": 1}
            ]
          },
          "commentsCount": 5
        }
        """#
    }

    @Test("Форматирование: известные типы, ссылка и упоминание; незнакомые и пустые пропускаются")
    func formatting() {
        let json = #"{"elements":[{"type":"STRONG","from":0,"length":4},{"type":"LINK","from":5,"length":4,"attributes":{"url":"https://max.ru"}},{"type":"USER_MENTION","from":10,"length":5,"entityId":77},{"type":"ANIMOJI","from":0,"length":1},{"type":"EMPHASIZED","from":1,"length":0}]}"#
        let content = MessageContentCodec.decode(json)
        #expect(content.formatting == [
            TextSpan(kind: .strong, from: 0, length: 4),
            TextSpan(kind: .link, from: 5, length: 4, url: "https://max.ru"),
            TextSpan(kind: .mention, from: 10, length: 5, userId: "77"),
        ])
        #expect(MessageContentCodec.decode(MessageContentCodec.encode(content)) == content)
        // Старая запись без поля formatting читается как раньше.
        let old = MessageContentCodec.decode(#"{"attachments":[],"reactions":[{"emoji":"👍","count":1,"mine":true}]}"#)
        #expect(old.reactions.count == 1)
        #expect(old.formatting == nil)
    }

    @Test("Миниатюра previewData: массив байтов и data-адрес base64")
    func previewData() throws {
        let json = #"{"attaches":[{"_type":"PHOTO","photoId":1,"baseUrl":"https://i.example/1","previewData":[82,73,70,70]},{"_type":"VIDEO","videoId":2,"previewData":"data:image/webp;base64,UklGRg=="}]}"#
        let content = MessageContentCodec.decode(json)
        #expect(content.attachments.first?.photo?.preview == Data([82, 73, 70, 70]))
        #expect(content.attachments.last?.video?.preview == Data([82, 73, 70, 70]))
        #expect(content.attachments.last?.video?.url == nil)
        let stored = MessageContentCodec.decode(MessageContentCodec.encode(content))
        #expect(stored == content)
    }
}

@Suite("Контент в базе")
struct MessageContentStoreTests {
    @Test("Запись базы правленого сообщения читается целиком, а не как фрагмент сервера")
    func editedRoundTrip() {
        let content = MessageContent(
            reply: MessageReply(messageId: "5", authorName: "Анна", preview: "Привет", kind: .text),
            reactions: [MessageReaction(emoji: "❤️", count: 2, mine: true)],
            edited: true
        )
        #expect(MessageContentCodec.decode(MessageContentCodec.encode(content)) == content)
    }

    @Test("Пустое эхо не стирает реакцию, непустой фрагмент заменяет её")
    func reactionSurvivesEmptyEcho() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        let heart = MessageContentCodec.encode(
            MessageContent(reactions: [MessageReaction(emoji: "❤️", count: 2, mine: true)])
        )
        let original = row("m1", text: "раз", contentJSON: heart)
        try await repository.upsert([original])
        try await repository.upsert([row("m1", text: "правка")])

        let kept = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(kept.text == "правка")
        #expect(kept.domain.content.reactions == [MessageReaction(emoji: "❤️", count: 2, mine: true)])

        let replacement = MessageContentCodec.encode(
            MessageContent(reactions: [MessageReaction(emoji: "👍", count: 4, mine: false)])
        )
        try await repository.upsert([row("m1", text: "правка", contentJSON: replacement)])
        let replaced = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(replaced.domain.content.reactions == [MessageReaction(emoji: "👍", count: 4, mine: false)])
    }

    @Test("Своя реакция переключается и остаётся после текстового эха")
    func toggleReaction() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        try await repository.upsert([row("m1", text: "раз", contentJSON: MessageContentCodec.encode(
            MessageContent(reactions: [MessageReaction(emoji: "❤️", count: 2, mine: false)])
        ))])
        try await repository.setReaction(messageId: "m1", emoji: "❤️")
        try await repository.setReaction(messageId: "m1", emoji: "👍")
        try await repository.upsert([row("m1", text: "эхо")])

        let stored = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(stored.domain.content.reactions == [
            MessageReaction(emoji: "❤️", count: 2, mine: false),
            MessageReaction(emoji: "👍", count: 1, mine: true),
        ])
    }

    @Test("Цитата исходящего переживает текстовое эхо сервера")
    func replySurvivesEcho() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.success(SentMessage(serverId: "srv-1", timestamp: Date(timeIntervalSince1970: 20)))])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([row("parent-1", text: "Исходное", at: 10)])
        try await repository.send(text: "ответ", chatId: "c1", replyTo: "parent-1")

        let sent = try #require(try await repository.page(chatId: "c1", before: nil).first { $0.text == "ответ" })
        #expect(sent.id.hasPrefix("local-"))
        #expect(sent.serverId == "srv-1")
        #expect(sent.domain.content.reply == MessageReply(
            messageId: "parent-1",
            authorName: "Сообщение",
            preview: "Исходное",
            kind: .text
        ))

        try await repository.upsert([row("srv-1", text: "ответ", at: 20)])
        let echoed = try #require(try await repository.page(chatId: "c1", before: nil).first { $0.serverId == "srv-1" })
        #expect(echoed.id == sent.id)
        #expect(echoed.domain.content.reply?.preview == "Исходное")
        #expect(echoed.domain.content.reply?.messageId == "parent-1")
    }

    @Test("Ответ уходит на сервер ссылкой на серверный id, цитата названа автором")
    func replyGoesToServer() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.success(SentMessage(serverId: "900", timestamp: Date(timeIntervalSince1970: 30)))])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([row("500", text: "Вопрос", at: 10, authorName: "Анна")])
        try await repository.send(text: "Ответ", chatId: "c1", replyTo: "500")
        #expect(await eventually { await api.sentReplies == ["500"] })
        let sent = try #require(try await repository.page(chatId: "c1", before: nil).first { $0.text == "Ответ" })
        #expect(sent.domain.content.reply?.authorName == "Анна")
        #expect(sent.domain.content.reply?.messageId == "500")
    }

    @Test("Удаление: серверное сообщение через сервер, неотправленное только локально, отказ сервера оставляет")
    func deleteMessages() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.offline)])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([row("500", text: "Серверное", at: 10), row("501", text: "Второе", at: 11)])
        try await repository.send(text: "Не ушло", chatId: "c1")
        let local = try #require(try await repository.page(chatId: "c1", before: nil).first { $0.text == "Не ушло" })

        try await repository.delete(messageIds: ["500"], chatId: "c1", forEveryone: true)
        try await repository.delete(messageIds: [local.id], chatId: "c1", forEveryone: false)
        let deletions = await api.deletions
        #expect(deletions.map(\.0) == [["500"]])
        #expect(deletions.map(\.1) == [true])
        #expect(try await repository.page(chatId: "c1", before: nil).map(\.text) == ["Второе"])

        await api.setDeleteResult(.failure(.offline))
        await #expect(throws: OrbitleError.self) {
            try await repository.delete(messageIds: ["501"], chatId: "c1", forEveryone: false)
        }
        #expect(try await repository.page(chatId: "c1", before: nil).map(\.text) == ["Второе"])
    }

    @Test("Правка: текст и пометка «изменено» после ответа сервера; отказ оставляет прежний текст")
    func editMessage() async throws {
        let api = FakeMaxAPI()
        await api.setEditResult(.success(MessageRecord(
            id: "500", serverId: "500", chatId: "c1", authorId: "bob", text: "Новый текст",
            timestamp: Date(timeIntervalSince1970: 10), status: .sent, contentJSON: #"{"edited":true}"#
        )))
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([row("500", text: "Старый", at: 10)])
        try await repository.edit(messageId: "500", chatId: "c1", text: " Новый текст ")
        let edited = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(edited.text == "Новый текст")
        #expect(edited.domain.content.edited == true)
        #expect(await api.edits.map(\.1) == ["Новый текст"])

        await api.setEditResult(.failure(.offline))
        await #expect(throws: OrbitleError.self) {
            try await repository.edit(messageId: "500", chatId: "c1", text: "Ещё раз")
        }
        #expect(try await repository.page(chatId: "c1", before: nil).first?.text == "Новый текст")
        await #expect(throws: OrbitleError.self) {
            try await repository.edit(messageId: "local-9", chatId: "c1", text: "x")
        }
    }

    @Test("Пересылка записывает новое сообщение в целевой чат; неотправленное не пересылается")
    func forwardMessage() async throws {
        let api = FakeMaxAPI()
        let forwarded = MessageRecord(
            id: "900", serverId: "900", chatId: "c2", authorId: "me", text: "", timestamp: Date(timeIntervalSince1970: 40),
            status: .sent, contentJSON: #"{"link":{"type":"FORWARD","messageId":"500","message":{"text":"Оригинал","senderName":"Анна"}}}"#
        )
        await api.setForwardResult(.success(forwarded))
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([row("500", text: "Оригинал", at: 10)])
        try await repository.forward(messageId: "500", from: "c1", to: "c2")
        let copy = try #require(try await repository.page(chatId: "c2", before: nil).first)
        #expect(copy.domain.content.forward == MessageForward(authorName: "Анна", text: "Оригинал"))
        #expect(copy.domain.displayText == "Оригинал")
        await #expect(throws: OrbitleError.self) {
            try await repository.forward(messageId: "local-1", from: "c1", to: "c2")
        }
    }

    @Test("Комментарий живёт в треде, лента и очередь его не видят")
    func commentsStayInThread() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.offline)])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([row("post-1", text: "Пост", at: 10)])
        try await repository.send(text: "текст", chatId: "c1")
        try await repository.sendComment(text: "  заметка  ", chatId: "c1", postId: "post-1")
        try await repository.sendComment(text: "   ", chatId: "c1", postId: "post-1")

        let page = try await repository.page(chatId: "c1", before: nil)
        #expect(page.allSatisfy { $0.threadOf.isEmpty })
        #expect(page.contains { $0.text == "Пост" })
        #expect(page.contains { $0.text == "текст" })
        #expect(!page.contains { $0.text == "заметка" })
        #expect(page.first { $0.id == "post-1" }?.domain.content.comments?.count == 1)

        let thread = try await repository.commentPage(chatId: "c1", postId: "post-1")
        #expect(thread.map(\.text) == ["заметка"])
        #expect(thread.first?.content.threadOf == "post-1")
        #expect(thread.first?.status == .sent)
        #expect(await repository.pendingOutgoing().map(\.text) == ["текст"])

        var main = repository.messages(chatId: "c1").makeAsyncIterator()
        let shown = try #require(await main.next())
        #expect(shown.contains { $0.text == "Пост" })
        #expect(!shown.contains { $0.text == "заметка" })

        var comments = repository.comments(chatId: "c1", postId: "post-1").makeAsyncIterator()
        let posted = try #require(await comments.next())
        #expect(posted.map(\.text) == ["заметка"])
    }

    @Test("Страница ленты не забирает комментарии вместо сообщений")
    func pageSkipsThread() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        var records = (1...3).map { index in
            row("m\(index)", text: "m\(index)", at: TimeInterval(index))
        }
        records.append(row("c1", text: "комментарий", at: 100, threadOf: "m3"))
        records.append(row(
            "c2",
            text: "ещё",
            at: 101,
            contentJSON: MessageContentCodec.encode(MessageContent(threadOf: "m3")),
            threadOf: "m3"
        ))
        try await repository.upsert(records)

        let page = try await repository.page(chatId: "c1", before: nil, limit: 2)
        #expect(page.map(\.id) == ["m3", "m2"])
        let thread = try await repository.commentPage(chatId: "c1", postId: "m3")
        #expect(thread.map(\.id) == ["c1", "c2"])
    }

    @Test("Скачанный файл запоминается у вложения")
    func remembersDownload() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("orbitle-voice-\(UUID().uuidString).ogg")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let voice = VoiceContent(id: "a1", url: URL(string: "https://cdn.example/a.ogg"), durationMs: 3200)
        try await repository.upsert([row(
            "m1",
            text: "",
            contentJSON: MessageContentCodec.encode(MessageContent(attachments: [.voice(voice)]))
        )])
        await repository.noteDownloaded(messageId: "m1", attachmentId: "a1", localPath: file.path)

        let stored = try #require(try await repository.page(chatId: "c1", before: nil).first)
        let clip = try #require(stored.domain.content.voices.first)
        #expect(clip.localPath == file.path)
        #expect(clip.fileURL?.path == file.path)
        #expect(clip.durationMs == 3200)
    }

    @Test("Пустое имя не стирает уже известного автора")
    func authorSurvivesEmptyEcho() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        try await repository.upsert([row(
            "m1",
            text: "раз",
            authorName: "Анна",
            authorAvatarURL: "https://cdn.example/a.jpg"
        )])
        try await repository.upsert([row("m1", text: "эхо")])
        let kept = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(kept.domain.authorName == "Анна")
        #expect(kept.domain.authorAvatarURL == URL(string: "https://cdn.example/a.jpg"))

        try await repository.upsert([row(
            "m1",
            text: "эхо",
            authorName: "Борис",
            authorAvatarURL: "https://cdn.example/b.jpg"
        )])
        let replaced = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(replaced.domain.authorName == "Борис")
        #expect(replaced.domain.authorAvatarURL == URL(string: "https://cdn.example/b.jpg"))
    }

    @Test("Правка без фрагмента оставляет вложения, правка с фрагментом их заменяет")
    func editKeepsAttachmentsUntilAFragmentArrives() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        let photo = MessageContentCodec.encode(MessageContent(attachments: [
            .photo(PhotoContent(id: "p", url: URL(string: "https://cdn.example/p.jpg"), width: 800, height: 600)),
        ]))
        try await repository.upsert([row("m1", text: "раз", contentJSON: photo)])
        #expect(try await repository.applyEdit(row("m1", text: "новое")))
        let kept = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(kept.text == "новое")
        #expect(kept.domain.content.visuals.first?.photo?.id == "p")

        let file = MessageContentCodec.encode(MessageContent(attachments: [
            .file(FileContent(id: "f", name: "отчёт.pdf", size: 2048, url: URL(string: "https://cdn.example/f.pdf"))),
        ]))
        #expect(try await repository.applyEdit(row("m1", text: "файл", contentJSON: file)))
        let replaced = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(replaced.domain.content.files.first?.name == "отчёт.pdf")
        #expect(replaced.domain.content.visuals.isEmpty)
    }

    private func row(
        _ id: String,
        text: String,
        at seconds: TimeInterval = 1,
        contentJSON: String = "",
        threadOf: String = "",
        authorName: String = "",
        authorAvatarURL: String = ""
    ) -> MessageRecord {
        MessageRecord(
            id: id,
            serverId: id,
            chatId: "c1",
            authorId: "bob",
            text: text,
            timestamp: Date(timeIntervalSince1970: seconds),
            status: .sent,
            contentJSON: contentJSON,
            threadOf: threadOf,
            authorName: authorName,
            authorAvatarURL: authorAvatarURL
        )
    }
}
