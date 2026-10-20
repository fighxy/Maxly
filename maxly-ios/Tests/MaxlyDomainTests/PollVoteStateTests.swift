import Testing
@testable import MaxlyDomain

@Suite("Опрос: свой голос")
struct PollVoteStateTests {
    private let poll = PollContent(id: "p", title: "Q", answers: [
        PollAnswer(id: "1", text: "A"), PollAnswer(id: "2", text: "B"),
    ])

    @Test("Ответ на голос отмечает свой ответ, проценты и закрывает голосование")
    func appliesResult() {
        var next = poll
        #expect(next.canVote)
        next.apply(PollCountUpdate(pollId: "p", total: 4, votes: ["1": 3, "2": 1], myAnswerIds: ["1"]))
        #expect(next.voted)
        #expect(next.isMine("1"))
        #expect(!next.isMine("2"))
        #expect(next.answers.first?.mine == true)
        #expect(next.percent(of: next.answers[0]) == 75)
        #expect(next.showsResults)
        #expect(!next.canVote)
    }

    @Test("Смена голоса разрешена флагом, закрытый опрос не принимает голос")
    func revoteAndClosed() {
        var next = poll
        next.apply(PollCountUpdate(pollId: "p", total: 1, votes: ["2": 1], myAnswerIds: ["2"], revote: true))
        #expect(next.canVote)
        next.apply(PollCountUpdate(pollId: "p", total: 1, votes: ["2": 1], closed: true))
        #expect(next.isMine("2"))
        #expect(!next.canVote)
        #expect(PollContent.allowsRevote(flags: 4))
        #expect(PollContent.isClosed(flags: 8))
    }

    @Test("Обновление без своего голоса не стирает прежний")
    func keepsVote() {
        var next = poll
        next.apply(PollCountUpdate(pollId: "p", total: 1, votes: ["1": 1], myAnswerIds: ["1"]))
        next.apply(PollCountUpdate(pollId: "p", total: 2, votes: ["1": 1, "2": 1]))
        #expect(next.myAnswerIds == ["1"])
        #expect(!next.canVote)
    }

    @Test("poll.already.voted показывается по-человечески и не повторяется сам")
    func alreadyVotedText() {
        let error = MaxlyError.server(code: "poll.already.voted", text: nil)
        #expect(error.isPollAlreadyVoted)
        #expect(error.userMessage == "Вы уже проголосовали")
        #expect(!error.isTransient)
        #expect(MaxlyError.server(code: "poll.already.voted", text: "Vote failed").userMessage == "Вы уже проголосовали")
    }
}
