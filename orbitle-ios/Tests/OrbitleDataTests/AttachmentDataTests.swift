import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

private let photo = AttachmentDraft(kind: .photo, path: "/tmp/Outgoing/a.jpg", fileName: "image.jpg", size: 1_000, width: 800, height: 600)
private let video = AttachmentDraft(kind: .video, path: "/tmp/Outgoing/b.mp4", fileName: "video.mp4", size: 5_000, durationMs: 3_000)
private let file = AttachmentDraft(kind: .file, path: "/tmp/Outgoing/Отчёт.pdf", fileName: "Отчёт.pdf", size: 2_048)

/// Ответ сервера на фото: вложение с адресом, как его разбирает кодек.
private func sentPhoto(serverId: String = "900", at seconds: TimeInterval = 50) -> MessageRecord {
    MessageRecord(
        id: serverId,
        serverId: serverId,
        chatId: "c1",
        authorId: "me",
        text: "Подпись",
        timestamp: Date(timeIntervalSince1970: seconds),
        status: .sent,
        contentJSON: #"{"attaches":[{"_type":"PHOTO","photoId":77,"baseUrl":"https://i.example/p","width":800,"height":600}]}"#
    )
}

private func only(_ repository: MessageRepositoryImpl) async throws -> Message {
    let rows = try await repository.page(chatId: "c1", before: nil, limit: 50)
    #expect(rows.count == 1)
    return try #require(rows.first).domain
}

@Suite("Вложения: разбор")
struct AttachmentCodecTests {
    @Test("Карточка контакта: имя целиком или по частям, номер строкой или числом")
    func contact() throws {
        let full = MessageContentCodec.decode(#"{"attaches":[{"_type":"CONTACT","contactId":42,"name":"Мария Петрова","phone":"+79990000000","photoUrl":"https://i.example/a"}]}"#)
        let card = try #require(full.attachments.first?.contact)
        #expect(card.userId == "42")
        #expect(card.name == "Мария Петрова")
        #expect(card.phone == "+79990000000")
        #expect(card.avatarURL == URL(string: "https://i.example/a"))

        let parts = MessageContentCodec.decode(#"{"attaches":[{"_type":"CONTACT","contactId":"43","firstName":"Иван","lastName":"К","phoneNumber":79991112233}]}"#)
        let second = try #require(parts.attachments.first?.contact)
        #expect(second.name == "Иван К")
        #expect(second.phone == "79991112233")
    }

    @Test("Черновики вложений переживают запись в базу")
    func draftsRoundTrip() {
        var content = MessageContent.empty
        content.drafts = [photo, .contact(id: "42", name: "Мария")]
        let decoded = MessageContentCodec.decode(MessageContentCodec.encode(content))
        #expect(decoded.drafts == content.drafts)
        #expect(decoded.hasPendingUploads)
    }
}

@Suite("Вложения: клиент ядра")
struct AttachmentClientTests {
    @Test("Фото, видео и файл уходят одним sendMedia с подписью и числовой цитатой")
    func media() async throws {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        let result = await client.sendAttachments(chatId: "c1", drafts: [photo, video, file], caption: "Подпись", replyTo: "555") { _ in }
        #expect((try? result.get())?.serverId == "srv-1")
        let calls = await core.mediaCalls
        #expect(calls.count == 1)
        #expect(calls.first?.items == [
            CoreOutgoingMedia(path: photo.path, kind: "photo", fileName: "image.jpg"),
            CoreOutgoingMedia(path: video.path, kind: "video", fileName: "video.mp4"),
            CoreOutgoingMedia(path: file.path, kind: "file", fileName: "Отчёт.pdf"),
        ])
        #expect(calls.first?.caption == "Подпись")
        #expect(calls.first?.replyTo == "555")
    }

    @Test("Локальная цитата не уходит, контакт идёт отдельным sendContact")
    func contactAndLocalReply() async throws {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        _ = await client.sendAttachments(chatId: "c1", drafts: [photo], caption: "", replyTo: "local-1") { _ in }
        #expect(await core.mediaCalls.first?.replyTo == "")

        _ = await client.sendAttachments(chatId: "c1", drafts: [.contact(id: "42", name: "Мария")], caption: "", replyTo: "7") { _ in }
        let contacts = await core.contactCalls
        #expect(contacts.count == 1)
        #expect(contacts.first?.contactId == "42")
        #expect(contacts.first?.replyTo == "7")
    }

    @Test("Голосовое и кружок уходят своим запросом записи, с длительностью и дорожкой")
    func recordings() async throws {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        let voice = AttachmentDraft.voice(path: "/tmp/voice.ogg", durationMs: 4_200, waveform: [0, 60, 120])
        _ = await client.sendAttachments(chatId: "c1", drafts: [voice], caption: "", replyTo: "9") { _ in }
        let note = AttachmentDraft.videoNote(path: "/tmp/note.mp4", durationMs: 7_000, side: 480)
        _ = await client.sendAttachments(chatId: "c1", drafts: [note], caption: "", replyTo: nil) { _ in }
        let calls = await core.recordingCalls
        #expect(calls.map(\.kind) == ["voice", "videoNote"])
        #expect(calls.first?.durationMs == 4_200)
        #expect(calls.first?.wave == [0, 60, 120])
        #expect(calls.first?.replyTo == "9")
        #expect(calls.last?.path == "/tmp/note.mp4")
        #expect(await core.mediaCalls.isEmpty)

        let mixed = await client.sendAttachments(chatId: "c1", drafts: [voice, photo], caption: "", replyTo: nil) { _ in }
        #expect(throws: MaxAPIError.self) { try mixed.get() }
    }

    @Test("Черновик голосового виден в пузыре сразу: дорожка, длительность, локальный файл")
    func recordingPreview() {
        let voice = AttachmentDraft.voice(path: "/tmp/voice.ogg", durationMs: 4_200, waveform: [1, 2]).preview(index: 0)
        #expect(voice.voice?.durationMs == 4_200)
        #expect(voice.voice?.waveform == [1, 2])
        #expect(voice.voice?.localPath == "/tmp/voice.ogg")
        let note = AttachmentDraft.videoNote(path: "/tmp/note.mp4", durationMs: 7_000, side: 480).preview(index: 0)
        #expect(note.video?.isRound == true)
        #expect(note.video?.width == 480)
    }

    @Test("Контакт вместе с файлами и файл без пути отклоняются без запроса")
    func invalid() async throws {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        let mixed = await client.sendAttachments(chatId: "c1", drafts: [photo, .contact(id: "42", name: "М")], caption: "", replyTo: nil) { _ in }
        #expect(throws: MaxAPIError.self) { try mixed.get() }
        let empty = await client.sendAttachments(chatId: "c1", drafts: [AttachmentDraft(kind: .file)], caption: "", replyTo: nil) { _ in }
        #expect(throws: MaxAPIError.self) { try empty.get() }
        #expect(await core.mediaCalls.isEmpty)
        #expect(await core.contactCalls.isEmpty)
    }

    @Test("Ошибка ядра становится ошибкой API")
    func failure() async throws {
        let core = FakeMaxCore()
        await core.failSend()
        let client = MaxAPIClient(core: core)
        let result = await client.sendAttachments(chatId: "c1", drafts: [photo], caption: "", replyTo: nil) { _ in }
        #expect(throws: MaxAPIError.self) { try result.get() }
    }
}

@Suite("Вложения: отправка")
struct AttachmentRepositoryTests {
    @Test("Пузырь с локальной копией сразу, после ответа — отправлено, путь к копии остаётся")
    func optimisticThenSent() async throws {
        let api = FakeMaxAPI()
        await api.setHoldUploads(true)
        await api.setAttachmentResults([.success(sentPhoto())])
        let (repository, _) = try await makeMessageStack(api: api)

        try await repository.sendAttachments([photo], caption: "  Подпись ", chatId: "c1", replyTo: nil)
        let pending = try await only(repository)
        #expect(pending.status == .sending)
        #expect(pending.text == "Подпись")
        #expect(pending.content.attachments.first?.photo?.localPath == photo.path)
        #expect(pending.content.hasPendingUploads)

        await api.setHoldUploads(false)
        await repository.waitForUpload(localId: pending.id)
        let sent = try await only(repository)
        #expect(sent.status == .sent)
        #expect(sent.serverId == "900")
        #expect(!sent.content.hasPendingUploads)
        let stored = try #require(sent.content.attachments.first?.photo)
        #expect(stored.url == URL(string: "https://i.example/p"))
        #expect(stored.localPath == photo.path)
        #expect(await api.attachmentCalls.map(\.caption) == ["Подпись"])
    }

    @Test("Эхо своего сообщения, пришедшее раньше ответа, не дублирует пузырь")
    func echoMerged() async throws {
        let api = FakeMaxAPI()
        await api.setHoldUploads(true)
        await api.setAttachmentResults([.success(sentPhoto())])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.sendAttachments([photo], caption: "Подпись", chatId: "c1", replyTo: nil)
        let localId = try await only(repository).id
        try await repository.upsert([sentPhoto()])
        await api.setHoldUploads(false)
        await repository.waitForUpload(localId: localId)
        let rows = try await repository.page(chatId: "c1", before: nil, limit: 50)
        #expect(rows.count == 1)
        #expect(rows.first?.id == localId)
    }

    @Test("Ошибка — «не отправлено», повтор загружает заново")
    func failThenRetry() async throws {
        let api = FakeMaxAPI()
        await api.setAttachmentResults([.failure(.offline), .success(sentPhoto())])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.sendAttachments([photo], caption: "", chatId: "c1", replyTo: nil)
        let localId = try await only(repository).id
        await repository.waitForUpload(localId: localId)
        let failed = try await only(repository)
        #expect(failed.status == .failed)
        #expect(failed.content.hasPendingUploads)

        try await repository.retry(messageId: localId)
        await repository.waitForUpload(localId: localId)
        #expect(try await only(repository).status == .sent)
        #expect(await api.attachmentCalls.count == 2)
        #expect(await api.attachmentCalls.last?.drafts == [photo])
    }

    @Test("Отмена идущей загрузки убирает сообщение")
    func cancel() async throws {
        let api = FakeMaxAPI()
        await api.setHoldUploads(true)
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.sendAttachments([video], caption: "", chatId: "c1", replyTo: nil)
        let localId = try await only(repository).id
        #expect(await repository.isUploading(localId: localId))
        await repository.cancelUpload(messageId: localId)
        await repository.waitForUpload(localId: localId)
        #expect(try await repository.page(chatId: "c1", before: nil, limit: 50).isEmpty)
    }

    @Test("Упавшее сообщение с вложениями отмена тоже удаляет")
    func cancelFailed() async throws {
        let api = FakeMaxAPI()
        await api.setAttachmentResults([.failure(.offline)])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.sendAttachments([file], caption: "", chatId: "c1", replyTo: nil)
        let localId = try await only(repository).id
        await repository.waitForUpload(localId: localId)
        await repository.cancelUpload(messageId: localId)
        #expect(try await repository.page(chatId: "c1", before: nil, limit: 50).isEmpty)
    }

    @Test("Очередь текстов сообщения с вложениями не берёт")
    func outboxSkipsDrafts() async throws {
        let api = FakeMaxAPI()
        await api.setHoldUploads(true)
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.sendAttachments([photo], caption: "", chatId: "c1", replyTo: nil)
        let localId = try await only(repository).id
        #expect(await repository.pendingOutgoing().isEmpty)
        #expect(await repository.outgoing(localId: localId) == nil)
        #expect(await api.sendCalls == 0)
        await repository.cancelUpload(messageId: localId)
        await repository.waitForUpload(localId: localId)
    }

    @Test("После перезапуска зависшая загрузка становится «не отправлено»")
    func staleAfterRestart() async throws {
        let stack = try SwiftDataStack(inMemory: true)
        let api = FakeMaxAPI()
        var content = MessageContent.empty
        content.attachments = [photo.preview(index: 0)]
        content.drafts = [photo]
        let before = MessageRepositoryImpl.make(stack: stack, api: api)
        try await before.upsert([MessageRecord(
            id: "local-1", chatId: "c1", authorId: "me", text: "", timestamp: Date(timeIntervalSince1970: 5),
            status: .sending, contentJSON: MessageContentCodec.encode(content)
        )])
        let after = MessageRepositoryImpl.make(stack: stack, api: api)
        await after.attach(outbox: OutboxQueue(api: api, sleep: { _ in }))
        let rows = try await after.page(chatId: "c1", before: nil, limit: 50)
        #expect(rows.first?.status == .failed)
        #expect(await api.attachmentCalls.isEmpty)
    }

    @Test("Ход загрузки: растёт и исчезает после конца")
    func progress() async throws {
        let api = FakeMaxAPI()
        await api.setHoldUploads(true)
        await api.setAttachmentResults([.success(sentPhoto())])
        let (repository, _) = try await makeMessageStack(api: api)
        let stream = repository.uploadProgress()
        try await repository.sendAttachments([photo], caption: "", chatId: "c1", replyTo: nil)
        let localId = try await only(repository).id

        var seen: [Double] = []
        for await snapshot in stream {
            if let value = snapshot[localId] {
                if seen.last != value { seen.append(value) }
                if value >= 0.25 { break }
            }
        }
        #expect(seen.last == 0.25)
        #expect(seen == seen.sorted())

        await api.setHoldUploads(false)
        await repository.waitForUpload(localId: localId)
        #expect(await repository.isUploading(localId: localId) == false)
    }

    @Test("Пустой набор вложений отклоняется")
    func empty() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        await #expect(throws: OrbitleError.self) {
            try await repository.sendAttachments([], caption: "x", chatId: "c1", replyTo: nil)
        }
    }
}
