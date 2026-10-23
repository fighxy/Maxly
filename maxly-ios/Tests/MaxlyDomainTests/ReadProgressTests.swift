import Foundation
import Testing
@testable import MaxlyDomain

/// Сообщение с серверным id `id` и временем `id` секунд.
private func message(_ id: Int, author: String = "bob", status: MessageStatus = .sent) -> Message {
    Message(id: "\(id)", serverId: "\(id)", chatId: "c", authorId: author, text: "m\(id)",
            timestamp: Date(timeIntervalSince1970: Double(id)), status: status)
}

private let feed = (1...5).map { message($0) }
private func mine(_ message: Message) -> Bool { message.authorId == "me" }

@Suite("Что прочитано за показ чата")
struct ReadProgressTests {
    @Test("Не у низа читается самое новое увиденное, у низа — последнее")
    func seenAndFollowing() {
        var progress = ReadProgress()
        progress.open(position: 0)
        #expect(progress.candidate(shown: feed, live: feed, isOutgoing: mine) == nil)
        progress.see(3_000, following: false)
        #expect(progress.candidate(shown: feed, live: feed, isOutgoing: mine)?.messageId == "3")
        progress.see(nil, following: true)
        #expect(progress.candidate(shown: feed, live: feed, isOutgoing: mine)?.messageId == "5")
    }

    @Test("Прочитанное до открытия не отмечается: своя позиция и место при открытии")
    func floor() {
        var progress = ReadProgress()
        progress.open(position: 2_000)
        progress.see(2_000, following: false)
        #expect(progress.candidate(shown: feed, live: feed, isOutgoing: mine) == nil)
        // Непрочитанных при открытии не было: последнее уже прочитано, у низа отмечать нечего.
        progress.noteReadAtOpen(5_000)
        progress.see(nil, following: true)
        #expect(progress.candidate(shown: feed, live: feed, isOutgoing: mine) == nil)
        let next = feed + [message(6)]
        #expect(progress.candidate(shown: next, live: next, isOutgoing: mine)?.messageId == "6")
    }

    @Test("Разделитель, вставший позже, опускает место при открытии, но не ниже своей позиции")
    func anchorLowersOpenedRead() {
        var progress = ReadProgress()
        progress.open(position: 1_000)
        progress.noteReadAtOpen(5_000)
        progress.noteReadAtOpen(2_000)
        #expect(progress.floor == 2_000)
        progress.noteReadAtOpen(0)
        #expect(progress.floor == 1_000)
    }

    @Test("Своё и неотправленное отметкой не бывают")
    func ownAndUnsent() {
        var progress = ReadProgress()
        progress.open(position: 0)
        progress.noteReadAtOpen(4_000)
        progress.see(nil, following: true)
        let withOwn = feed + [message(6, author: "me")]
        #expect(progress.candidate(shown: withOwn, live: withOwn, isOutgoing: mine)?.messageId == "5")
        let withSending = feed + [message(7, status: .sending)]
        #expect(progress.candidate(shown: withSending, live: withSending, isOutgoing: mine)?.messageId == "5")
        let onlyOwnNew = Array(feed.prefix(4)) + [message(6, author: "me")]
        #expect(progress.candidate(shown: onlyOwnNew, live: onlyOwnNew, isOutgoing: mine) == nil)
    }

    @Test("Окно перехода: старая история ниже порога ничего не отмечает")
    func jumpWindowBelowFloor() {
        var progress = ReadProgress()
        progress.open(position: 50_000)
        let window = (10...15).map { message($0) }
        let live = (50...55).map { message($0) }
        progress.see(15_000, following: false)
        #expect(progress.candidate(shown: window, live: live, isOutgoing: mine) == nil)
    }

    @Test("Уход с экрана забывает увиденное, порог остаётся до нового открытия")
    func endShowing() {
        var progress = ReadProgress()
        progress.open(position: 0)
        progress.noteReadAtOpen(2_000)
        progress.see(4_000, following: true)
        progress.endShowing()
        #expect(progress.seen == 0)
        #expect(!progress.following)
        #expect(progress.floor == 2_000)
        #expect(progress.candidate(shown: feed, live: feed, isOutgoing: mine) == nil)
        progress.open(position: 0)
        #expect(progress.floor == 0)
    }
}
