import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Сообщение с серверным id `id` и временем `id` секунд; `mentions` — кого упомянули.
private func message(_ id: Int, author: String = "bob", mentions: [String] = []) -> Message {
    let spans = mentions.map { TextSpan(kind: .mention, from: 0, length: 2, userId: $0) }
    return Message(
        id: "\(id)", serverId: "\(id)", chatId: "c", authorId: author, text: "@x m\(id)",
        timestamp: Date(timeIntervalSince1970: Double(id)), status: .sent,
        content: MessageContent(formatting: spans.isEmpty ? nil : spans)
    )
}

@Suite("Непрочитанные упоминания и флаги ленты")
@MainActor
struct UnreadMentionsTests {
    private func opened(_ repository: FakeMessageRepository, unread: Int, feed: [Message]) async -> ChatViewModel {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.noteUnreadOnOpen(unread)
        await model.loadLatest()
        model.activate()
        repository.emit(feed)
        _ = await eventually { model.messages.count == feed.count }
        return model
    }

    @Test("«@» считает упоминания себя ниже прочитанного; переход и прокрутка их снимают")
    func mentions() async {
        let repository = FakeMessageRepository()
        let feed = [
            message(1, mentions: ["me"]),           // прочитано до открытия
            message(2),
            message(3, mentions: ["me"]),
            message(4, mentions: ["alice"]),        // не себя
            message(5, mentions: ["me"]),
            message(6),
        ]
        let model = await opened(repository, unread: 4, feed: feed)
        #expect(model.unreadAnchorId == "3")
        #expect(model.unreadMentions == ["3", "5"])
        model.jumpToNextMention()
        #expect(model.unreadMentions == ["5"])
        #expect(await eventually { model.highlightedId == "3" })
        // Долистали ниже пятого — упоминаний не осталось.
        model.noteBottomVisible("6")
        #expect(model.unreadMentions.isEmpty)
        model.deactivate()
    }

    @Test("Новое упоминание ниже экрана добавляется, своё сообщение — не упоминание")
    func newMention() async {
        let repository = FakeMessageRepository()
        let feed = [message(1), message(2)]
        let model = await opened(repository, unread: 0, feed: feed)
        #expect(model.unreadMentions.isEmpty)
        repository.emit(feed + [message(3, author: "me", mentions: ["me"]), message(4, mentions: ["me"])])
        _ = await eventually { model.messages.count == 4 }
        #expect(model.unreadMentions == ["4"])
        model.deactivate()
    }

    @Test("Флаги ленты: пустая сверенная история и свои сообщения")
    func historyFlags() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, unread: 0, feed: [])
        #expect(await eventually { model.isHistoryEmpty })
        #expect(!model.hasOwnMessages)
        repository.emit([message(1), message(2, author: "me")])
        _ = await eventually { model.messages.count == 2 }
        #expect(!model.isHistoryEmpty)
        #expect(model.hasOwnMessages)
        model.deactivate()
    }
}
