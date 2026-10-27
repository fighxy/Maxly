import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private actor FakeComments: CommentsRepository {
    private var stored: [Message]
    private var sendError: MaxlyError?
    /// Отказы на загрузку по порядку, затем обычные ответы.
    private var loadErrors: [MaxlyError]
    private(set) var requests: [Date?] = []

    init(_ stored: [Message], sendError: MaxlyError? = nil, loadErrors: [MaxlyError] = []) {
        self.stored = stored
        self.sendError = sendError
        self.loadErrors = loadErrors
    }

    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(MaxlyError) -> [Message] {
        requests.append(before)
        if !loadErrors.isEmpty { throw loadErrors.removeFirst() }
        let older = stored
            .filter { message in before.map { message.timestamp < $0 } ?? true }
            .sorted { $0.timestamp < $1.timestamp }
        return Array(older.suffix(limit))
    }

    func comments(chatId: String, postId: String, after: Date, limit: Int) async throws(MaxlyError) -> [Message] {
        requests.append(after)
        if !loadErrors.isEmpty { throw loadErrors.removeFirst() }
        let newer = stored.filter { $0.timestamp > after }.sorted { $0.timestamp < $1.timestamp }
        return Array(newer.prefix(limit))
    }

    func send(text: String, chatId: String, postId: String) async throws(MaxlyError) -> Message {
        if let sendError { throw sendError }
        let message = Message(id: "srv-\(stored.count)", chatId: chatId, authorId: "me", text: text, timestamp: .now, status: .sent)
        stored.append(message)
        return message
    }
}

/// Сервер, который не отдаёт страницу вперёд от поста: остаются последние комментарии.
private actor FakeEmptyForward: CommentsRepository {
    private let stored: [Message]

    init(_ stored: [Message]) { self.stored = stored }

    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(MaxlyError) -> [Message] {
        Array(stored.suffix(limit))
    }

    func comments(chatId: String, postId: String, after: Date, limit: Int) async throws(MaxlyError) -> [Message] { [] }

    func send(text: String, chatId: String, postId: String) async throws(MaxlyError) -> Message { throw .invalidRequest }
}

@Suite("Комментарии поста")
@MainActor
struct CommentsViewModelTests {
    private let post = Message(
        id: "p1", chatId: "c", authorId: "channel", text: "Пост", timestamp: Date(timeIntervalSince1970: 1), status: .sent,
        content: MessageContent(comments: CommentSummary(count: 5))
    )

    private func comment(_ index: Int) -> Message {
        Message(
            id: "k\(index)", chatId: "c", authorId: index.isMultiple(of: 2) ? "anna" : "bob", text: "Комментарий \(index)",
            timestamp: Date(timeIntervalSince1970: TimeInterval(100 + index)), status: .sent, authorName: index.isMultiple(of: 2) ? "Анна" : "Боб"
        )
    }

    @Test("Обсуждение с первого комментария, затем более новые, без повторов и по времени")
    func paging() async {
        let repository = FakeComments((0..<5).map(comment))
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository, pageSize: 3)
        #expect(model.title == "5 комментариев")
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.comments.map(\.id) == ["k0", "k1", "k2"])
        #expect(model.hasNewer)
        await model.loadNewer()
        #expect(model.comments.map(\.id) == ["k0", "k1", "k2", "k3", "k4"])
        #expect(!model.hasNewer)
        await model.load()
        // Первая страница — от времени поста, следующая — от последнего загруженного.
        #expect(await repository.requests == [post.timestamp, comment(2).timestamp])
    }

    @Test("Свой отправленный комментарий не сдвигает страницы: середина обсуждения догружается")
    func sentCommentKeepsCursor() async {
        let repository = FakeComments((0..<5).map(comment))
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository, pageSize: 3)
        await model.load()
        model.draft = "Мой"
        await model.send()
        await model.loadNewer()
        #expect(model.comments.map(\.id).prefix(5) == ["k0", "k1", "k2", "k3", "k4"])
        #expect(model.comments.last?.text == "Мой")
    }

    @Test("Страница от поста пуста, а счётчик говорит, что комментарии есть: показываются последние")
    func fallsBackToLatest() async {
        let undated = FakeEmptyForward((0..<2).map(comment))
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: undated, pageSize: 3)
        await model.load()
        #expect(model.comments.map(\.id) == ["k0", "k1"])
        #expect(!model.hasNewer)
    }

    @Test("Сервер просит подождать: окно само повторяет загрузку один раз")
    func retriesOnceAfterRateLimit() async {
        let limit = MaxlyError.server(code: MaxlyError.rateLimitCode, text: nil)
        let repository = FakeComments([comment(0)], loadErrors: [limit])
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository, rateLimitRetry: .zero)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.comments.map(\.id) == ["k0"])
        #expect(await repository.requests.count == 2)

        let twice = FakeComments([comment(0)], loadErrors: [limit, limit])
        let failing = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: twice, rateLimitRetry: .zero)
        await failing.load()
        #expect(failing.state == .failed(limit.userMessage ?? ""))
        #expect(await twice.requests.count == 2)

        // Другие ошибки не повторяются сами.
        let offline = FakeComments([], loadErrors: [.networkUnavailable])
        let once = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: offline, rateLimitRetry: .zero)
        await once.load()
        #expect(await offline.requests.count == 1)
    }

    @Test("Пустое обсуждение предлагает написать первый комментарий")
    func empty() async {
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: FakeComments([]))
        await model.load()
        #expect(model.emptyText != nil)
        #expect(model.title == "Комментарии")
    }

    @Test("Свой комментарий уходит на сервер и встаёт в конец")
    func send() async {
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: FakeComments([comment(0)]))
        await model.load()
        model.draft = "  Привет  "
        await model.send()
        #expect(model.draft.isEmpty)
        #expect(model.comments.last?.text == "Привет")
        #expect(model.comments.last?.status == .sent)
        #expect(model.isOutgoing(model.comments.last!))
    }

    @Test("Ошибка отправки: комментарий помечен, текст вернулся в поле")
    func sendFails() async {
        let model = CommentsViewModel(
            chatId: "c", post: post, currentUserId: "me",
            comments: FakeComments([], sendError: .networkUnavailable)
        )
        await model.load()
        model.draft = "Привет"
        await model.send()
        #expect(model.comments.last?.status == .failed)
        #expect(model.draft == "Привет")
        #expect(model.errorMessage == MaxlyError.networkUnavailable.userMessage)
    }
}
