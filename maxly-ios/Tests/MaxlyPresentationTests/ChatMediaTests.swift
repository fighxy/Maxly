import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private actor FakeLinks: MediaLinkResolver {
    private(set) var requests: [String] = []
    private let links: [String: URL]

    init(_ links: [String: URL]) { self.links = links }

    func link(chatId: String, messageId: String, kind: MediaLinkKind, attachmentId: String) async throws(MaxlyError) -> URL {
        requests.append("\(kind.rawValue):\(chatId):\(messageId):\(attachmentId)")
        guard let url = links[attachmentId] else { throw .networkUnavailable }
        return url
    }
}

private actor FakeDownloads: MediaRepository {
    private(set) var fetched: [URL] = []
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    func preview(for item: MediaItem) async throws(MaxlyError) -> URL {
        fetched.append(item.url)
        let file = directory.appending(path: item.id)
        try? Data("pdf".utf8).write(to: file)
        return file
    }

    nonisolated func download(_ item: MediaItem) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func clearCache() async {}
}

@Suite("Экран чата: видео и файлы по ссылке сервера")
@MainActor
struct ChatMediaLinkTests {
    private func message(_ attachments: [ChatAttachment]) -> Message {
        Message(
            id: "42",
            chatId: "c",
            authorId: "bob",
            text: "",
            timestamp: .now,
            status: .sent,
            content: MessageContent(attachments: attachments)
        )
    }

    @Test("Видео без адреса: ссылка у сервера, затем просмотр с роликом")
    func videoLink() async throws {
        let play = try #require(URL(string: "https://video.example/v.mp4"))
        let links = FakeLinks(["77": play])
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), links: links)
        let video = VideoContent(id: "77", url: nil, posterURL: URL(string: "https://cdn.example/t.jpg"), durationMs: 5000)
        model.presentMedia(message([.video(video)]), startId: "77")
        #expect(model.loadingMediaId == "77")
        #expect(await eventually { model.viewer != nil })
        #expect(model.viewer?.slides.first?.playURL == play)
        #expect(model.viewer?.slides.first?.isVideo == true)
        #expect(model.loadingMediaId == nil)
        #expect(await links.requests == ["video:c:42:77"])
    }

    @Test("Кружок играет в ленте, а не на весь экран; повторное касание его останавливает")
    func roundPlaysInline() async throws {
        let play = try #require(URL(string: "https://video.example/r.mp4"))
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), links: FakeLinks(["88": play]))
        let round = VideoContent(id: "88", url: nil, durationMs: 3000, isRound: true)
        let note = message([.video(round)])
        model.presentMedia(note, startId: "88")
        #expect(await eventually { model.roundPlayback != nil })
        #expect(model.roundPlayback == RoundPlayback(id: "88", url: play))
        #expect(model.viewer == nil)
        model.presentMedia(note, startId: "88")
        #expect(model.roundPlayback == nil)
        model.presentMedia(note, startId: "88")
        #expect(model.roundPlayback?.id == "88")
        model.stopRound(id: "88")
        #expect(model.roundPlayback == nil)
    }

    @Test("Ссылка не пришла: кадр открывается постером, экран говорит, что видео недоступно")
    func videoLinkFails() async throws {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), links: FakeLinks([:]))
        let video = VideoContent(id: "77", url: nil, posterURL: URL(string: "https://cdn.example/t.jpg"))
        model.presentMedia(message([.video(video)]), startId: "77")
        #expect(await eventually { model.viewer != nil })
        #expect(model.viewer?.slides.first?.isVideo == false)
        #expect(model.errorMessage == "Видео не удалось загрузить")
    }

    @Test("Файл без адреса: ссылка у сервера, скачивание и копия с настоящим именем")
    func fileLink() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try #require(URL(string: "https://files.example/get?id=9"))
        let downloads = FakeDownloads(directory: directory)
        let model = ChatViewModel(
            chatId: "c",
            currentUserId: "me",
            messages: FakeMessageRepository(),
            media: downloads,
            links: FakeLinks(["9": source])
        )
        let file = FileContent(id: "9", name: "Отчёт.pdf", size: 3)
        model.openFile(message([.file(file)]), attachmentId: "9")
        #expect(await eventually { model.openedFile != nil })
        #expect(model.openedFile?.url.lastPathComponent == "Отчёт.pdf")
        #expect(model.openedFile?.name == "Отчёт.pdf")
        #expect(await downloads.fetched == [source])
        #expect(model.loadingMediaId == nil)
    }
}

@Suite("Лента: серии, дни, время голосового")
struct ChatTranscriptFormatTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 3, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test("Один автор подряд слипается в пределах 15 минут и одного дня")
    func grouping() {
        let now = date(5, 12)
        let joined = ChatContentFormat.group(
            authorId: "a",
            date: now,
            previous: (authorId: "a", date: date(5, 11, 55)),
            next: (authorId: "a", date: date(5, 12, 20)),
            calendar: calendar
        )
        #expect(joined == BubbleGroup(joinsPrevious: true, joinsNext: false))
        let other = ChatContentFormat.group(
            authorId: "a",
            date: now,
            previous: (authorId: "b", date: date(5, 11, 59)),
            next: nil,
            calendar: calendar
        )
        #expect(other == .single)
        let empty = ChatContentFormat.group(
            authorId: "",
            date: now,
            previous: (authorId: "", date: now),
            next: nil,
            calendar: calendar
        )
        #expect(empty == .single)
    }

    @Test("Заголовок дня: сегодня, вчера, дата, дата с годом")
    func days() {
        let now = date(5, 12)
        #expect(ChatContentFormat.dayTitle(date(5, 1), now: now, calendar: calendar) == "Сегодня")
        #expect(ChatContentFormat.dayTitle(date(4, 23), now: now, calendar: calendar) == "Вчера")
        #expect(ChatContentFormat.dayTitle(date(1, 9), now: now, calendar: calendar) == "1 марта")
        #expect(ChatContentFormat.dayTitle(date(31, 9, month: 12, year: 2025), now: now, calendar: calendar) == "31 декабря 2025")
        #expect(ChatContentFormat.startsDay(date(5, 1), after: nil, calendar: calendar))
        #expect(ChatContentFormat.startsDay(date(5, 1), after: date(4, 23), calendar: calendar))
        #expect(!ChatContentFormat.startsDay(date(5, 13), after: date(5, 1), calendar: calendar))
    }

    @Test("Голосовое показывает прозвучавшее время, иначе длительность")
    func voiceClock() {
        #expect(ChatContentFormat.voiceClock(durationMs: 65_000, phase: .idle) == "1:05")
        #expect(ChatContentFormat.voiceClock(durationMs: 60_000, phase: .playing(0.5)) == "0:30")
        #expect(ChatContentFormat.voiceClock(durationMs: 60_000, phase: .paused(1.5)) == "1:00")
    }
}

@Suite("Экран чата: правка сообщения")
@MainActor
struct ChatEditTests {
    private func own(_ text: String, status: MessageStatus = .sent, serverId: String? = "77") -> Message {
        Message(id: "m1", serverId: serverId, chatId: "c", authorId: "me", text: text, timestamp: .now, status: status)
    }

    @Test("Править можно только свой отправленный текст; правка откладывает черновик и возвращает его")
    func editMode() {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        #expect(model.canEdit(own("Привет")))
        #expect(!model.canEdit(own("Привет", status: .sending, serverId: nil)))
        #expect(!model.canEdit(Message(id: "x", chatId: "c", authorId: "bob", text: "чужое", timestamp: .now, status: .sent)))
        model.draft = "черновик"
        model.beginEdit(own("Привет"))
        #expect(model.editTarget?.id == "m1")
        #expect(model.draft == "Привет")
        model.cancelEdit()
        #expect(model.editTarget == nil)
        #expect(model.draft == "черновик")
    }
}
