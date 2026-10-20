import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Репозиторий опросов: запоминает голоса, обновления и применённые счётчики.
private actor PollMessages: MessageRepository {
    private(set) var votes: [String] = []
    private(set) var refreshes = 0
    private(set) var applied: [PollCountUpdate] = []
    var voteResult: Result<PollCountUpdate, MaxlyError> = .success(PollCountUpdate(pollId: "p", total: 0, votes: [:]))
    var refreshed: [PollCountUpdate] = []
    var gate: Gate?

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) {}
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws(MaxlyError) -> PollCountUpdate {
        votes.append(answerId)
        if let gate { await gate.wait() }
        return try voteResult.get()
    }

    func refreshPolls(chatId: String, polls: [(messageId: String, pollId: String)]) async throws(MaxlyError) -> [PollCountUpdate] {
        refreshes += 1
        return refreshed
    }

    func applyPollCounts(chatId: String, messageId: String, update: PollCountUpdate) async { applied.append(update) }

    func set(voteResult: Result<PollCountUpdate, MaxlyError>) { self.voteResult = voteResult }
    func set(refreshed: [PollCountUpdate]) { self.refreshed = refreshed }
    func set(gate: Gate?) { self.gate = gate }
}

private func pollMessage(_ poll: PollContent) -> Message {
    Message(
        id: "m1", serverId: "100", chatId: "c", authorId: "anna", text: "",
        timestamp: Date(timeIntervalSince1970: 1), status: .sent,
        content: MessageContent(attachments: [.poll(poll)])
    )
}

private let openPoll = PollContent(id: "p", title: "Q", answers: [PollAnswer(id: "1", text: "A"), PollAnswer(id: "2", text: "B")])

@Suite("Опрос: голос в чате")
@MainActor
struct PollVoteTests {
    @Test("Результат голоса со своим ответом записывается в опрос")
    func appliesVoteResult() async {
        let repository = PollMessages()
        let result = PollCountUpdate(pollId: "p", total: 1, votes: ["1": 1], myAnswerIds: ["1"])
        await repository.set(voteResult: .success(result))
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.vote(pollMessage(openPoll), answerId: "1")
        #expect(await repository.applied == [result])
        #expect(model.errorMessage == nil)
    }

    @Test("Опрос с голосом без смены голоса не шлёт новый голос")
    func closedWhenVoted() async {
        let repository = PollMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        var voted = openPoll
        voted.myAnswerIds = ["1"]
        #expect(!model.canVote(in: voted))
        await model.vote(pollMessage(voted), answerId: "2")
        await model.castVotes(pollMessage(voted), answerIds: ["2"])
        #expect(await repository.votes.isEmpty)
        voted.revote = true
        #expect(model.canVote(in: voted))
    }

    @Test("poll.already.voted: без повтора, опрос обновляется, текст понятный")
    func alreadyVotedRefreshes() async {
        let repository = PollMessages()
        await repository.set(voteResult: .failure(.server(code: "poll.already.voted", text: nil)))
        let fresh = PollCountUpdate(pollId: "p", total: 3, votes: ["1": 2, "2": 1], myAnswerIds: ["2"])
        await repository.set(refreshed: [fresh])
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.vote(pollMessage(openPoll), answerId: "1")
        #expect(await repository.votes == ["1"])
        #expect(await repository.refreshes == 1)
        #expect(await repository.applied == [fresh])
        #expect(model.errorMessage == nil)
        #expect(model.notice == "Вы уже проголосовали")
        #expect(!model.canVote(in: openPoll))
        await model.vote(pollMessage(openPoll), answerId: "1")
        #expect(await repository.votes == ["1"])
    }

    @Test("Второе нажатие, пока голос в пути, второй голос не шлёт")
    func doubleTap() async {
        let repository = PollMessages()
        let gate = Gate()
        await repository.set(gate: gate)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let first = Task { await model.vote(pollMessage(openPoll), answerId: "1") }
        #expect(await eventually { await repository.votes.count == 1 })
        await model.vote(pollMessage(openPoll), answerId: "1")
        await gate.open()
        await first.value
        #expect(await repository.votes == ["1"])
    }
}
