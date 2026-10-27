import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Счётчики комментариев на «сервере»: запоминает спрошенные посты.
private actor CountingComments: CommentsRepository {
    private(set) var asked: [[String]] = []
    var failure: MaxlyError?

    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(MaxlyError) -> [Message] { [] }
    func comments(chatId: String, postId: String, after: Date, limit: Int) async throws(MaxlyError) -> [Message] { [] }
    func send(text: String, chatId: String, postId: String) async throws(MaxlyError) -> Message { throw .invalidRequest }

    func counts(chatId: String, postIds: [String]) async throws(MaxlyError) -> [String: Int] {
        asked.append(postIds)
        if let failure { throw failure }
        return Dictionary(uniqueKeysWithValues: postIds.map { ($0, 3) })
    }

    func set(failure: MaxlyError?) { self.failure = failure }
}

private func post(_ id: String) -> Message {
    Message(id: id, serverId: id, chatId: "c", authorId: "channel", text: "пост", timestamp: Date(), status: .sent)
}

@Suite("Комментарии к постам канала")
@MainActor
struct ChatCommentsModelTests {
    @Test("Счётчики спрашиваются один раз на пост; закрытое окно спрашивает свой пост заново")
    func countsOncePerPost() async {
        let repository = CountingComments()
        let model = ChatCommentsModel(chatId: "c", currentUserId: "me", repository: repository, messages: FakeMessageRepository())
        model.requestCounts(for: [post("1"), post("2")])
        #expect(await eventually { model.count(for: post("2")) == 3 })
        model.requestCounts(for: [post("1"), post("2")])
        model.open(post("1"))
        #expect(model.model(for: post("1")) != nil)
        model.close()
        #expect(model.opened == nil)
        #expect(await eventually { await repository.asked.count == 2 })
        #expect(await repository.asked == [["1", "2"], ["1"]])
    }

    @Test("После ошибки сервера счётчики не спрашиваются, пока не пройдёт пауза")
    func pauseAfterError() async {
        let repository = CountingComments()
        await repository.set(failure: .networkUnavailable)
        let model = ChatCommentsModel(chatId: "c", currentUserId: "me", repository: repository, messages: FakeMessageRepository())
        model.requestCounts(for: [post("1")])
        #expect(await eventually { await repository.asked.count == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        model.requestCounts(for: [post("1")])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await repository.asked.count == 1)
        #expect(model.count(for: post("1")) == nil)
    }

    @Test("Без хранилища комментариев окно не открывается")
    func unavailable() {
        let model = ChatCommentsModel(chatId: "c", currentUserId: "me", repository: nil, messages: FakeMessageRepository())
        model.open(post("1"))
        #expect(model.opened == nil)
        #expect(model.model(for: post("1")) == nil)
    }
}
