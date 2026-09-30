import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

private actor FakeComments: CommentsRepository {
    private var stored: [Message]
    private var sendError: OrbitleError?
    private(set) var requests: [Date?] = []

    init(_ stored: [Message], sendError: OrbitleError? = nil) {
        self.stored = stored
        self.sendError = sendError
    }

    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(OrbitleError) -> [Message] {
        requests.append(before)
        let older = stored
            .filter { message in before.map { message.timestamp < $0 } ?? true }
            .sorted { $0.timestamp < $1.timestamp }
        return Array(older.suffix(limit))
    }

    func send(text: String, chatId: String, postId: String) async throws(OrbitleError) -> Message {
        if let sendError { throw sendError }
        let message = Message(id: "srv-\(stored.count)", chatId: chatId, authorId: "me", text: text, timestamp: .now, status: .sent)
        stored.append(message)
        return message
    }
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

    @Test("Первая страница, затем более ранние, без повторов и по времени")
    func paging() async {
        let repository = FakeComments((0..<5).map(comment))
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository, pageSize: 3)
        #expect(model.title == "5 комментариев")
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.comments.map(\.id) == ["k2", "k3", "k4"])
        #expect(model.hasMore)
        await model.loadOlder()
        #expect(model.comments.map(\.id) == ["k0", "k1", "k2", "k3", "k4"])
        #expect(!model.hasMore)
        await model.load()
        #expect(await repository.requests.count == 2)
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
        #expect(model.errorMessage == OrbitleError.networkUnavailable.userMessage)
    }
}
