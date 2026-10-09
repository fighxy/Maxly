import Testing
@testable import MaxlyDomain

@Suite("Реакции")
struct ReactionsTests {
    private func counters(_ pairs: [(String, Int)]) -> [ReactionUpdate.Counter] {
        pairs.map { ReactionUpdate.Counter(emoji: $0.0, count: $0.1) }
    }

    @Test("Известная своя реакция отмечается, порядок сервера сохраняется")
    func knownMine() {
        let update = ReactionUpdate(counters: counters([("🔥", 3), ("👍", 1)]), mine: "👍", mineKnown: true)
        #expect(update.applied(to: []) == [
            MessageReaction(emoji: "🔥", count: 3, mine: false),
            MessageReaction(emoji: "👍", count: 1, mine: true),
        ])
    }

    @Test("Пуш без своей реакции оставляет прежнюю, пока её счётчик есть")
    func unknownMineKept() {
        let current = [MessageReaction(emoji: "❤️", count: 1, mine: true)]
        let push = ReactionUpdate(counters: counters([("❤️", 2), ("👍", 1)]), mine: nil, mineKnown: false)
        #expect(push.applied(to: current) == [
            MessageReaction(emoji: "❤️", count: 2, mine: true),
            MessageReaction(emoji: "👍", count: 1, mine: false),
        ])
        // Счётчик своей пропал: значит, её сняли с другого устройства.
        let gone = ReactionUpdate(counters: counters([("👍", 1)]), mine: nil, mineKnown: false)
        #expect(gone.applied(to: current) == [MessageReaction(emoji: "👍", count: 1, mine: false)])
    }

    @Test("Известное «своей нет» снимает отметку")
    func knownNone() {
        let current = [MessageReaction(emoji: "❤️", count: 2, mine: true)]
        let update = ReactionUpdate(counters: counters([("❤️", 1)]), mine: nil, mineKnown: true)
        #expect(update.applied(to: current) == [MessageReaction(emoji: "❤️", count: 1, mine: false)])
        #expect(ReactionUpdate.none.applied(to: current).isEmpty)
    }

    @Test("Пустые, нулевые и повторные счётчики отбрасываются")
    func junkDropped() {
        let update = ReactionUpdate(counters: counters([("", 4), ("👍", 0), ("🔥", 2), ("🔥", 5)]), mine: "🔥", mineKnown: true)
        #expect(update.applied(to: []) == [MessageReaction(emoji: "🔥", count: 2, mine: true)])
    }

    @Test("Своя реакция и сумма")
    func mineAndTotal() {
        let reactions = [
            MessageReaction(emoji: "🔥", count: 3, mine: false),
            MessageReaction(emoji: "👍", count: 2, mine: true),
        ]
        #expect(reactions.mine == "👍")
        #expect(reactions.total == 5)
        #expect([MessageReaction]().mine == nil)
    }

    @Test("Смена своей реакции: одна на сообщение")
    func toggleReplaces() {
        let start = [
            MessageReaction(emoji: "❤️", count: 2, mine: true),
            MessageReaction(emoji: "👍", count: 1, mine: false),
        ]
        let switched = start.toggled("👍")
        #expect(switched == [
            MessageReaction(emoji: "❤️", count: 1, mine: false),
            MessageReaction(emoji: "👍", count: 2, mine: true),
        ])
        #expect(switched.mine == "👍")
        #expect(switched.toggled("👍") == [
            MessageReaction(emoji: "❤️", count: 1, mine: false),
            MessageReaction(emoji: "👍", count: 1, mine: false),
        ])
    }
}
