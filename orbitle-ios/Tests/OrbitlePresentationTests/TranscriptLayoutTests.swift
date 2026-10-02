import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Раскладка ленты")
struct TranscriptLayoutTests {
    private func message(_ id: String, author: String, name: String = "", at seconds: TimeInterval) -> Message {
        Message(id: id, chatId: "c", authorId: author, text: id, timestamp: Date(timeIntervalSince1970: seconds), status: .sent, authorName: name)
    }

    @Test("Разделитель дня, склейка одного автора, имя над первым и аватар у последнего")
    func rows() {
        let day: TimeInterval = 86_400
        let messages = [
            message("1", author: "bob", name: "Боб", at: 10 * day),
            message("2", author: "bob", name: "Боб", at: 10 * day + 30),
            message("3", author: "me", at: 10 * day + 60),
            message("4", author: "bob", name: "Боб", at: 11 * day),
        ]
        let rows = TranscriptLayout.rows(messages, currentUserId: "me", now: Date(timeIntervalSince1970: 20 * day))
        #expect(rows.map(\.id) == ["1", "2", "3", "4"])
        #expect(rows.map { $0.dayTitle != nil } == [true, false, false, true])
        #expect(rows.map(\.isOutgoing) == [false, false, true, false])
        #expect(rows.map(\.showsAuthorName) == [true, false, false, true])
        #expect(rows.map(\.showsAuthorAvatar) == [false, true, false, true])
        #expect(rows[0].group.joinsNext && rows[1].group.joinsPrevious)
        #expect(!rows[1].group.joinsNext)
    }

    @Test("Модель держит строки и версию состава: правка текста версию не двигает")
    @MainActor
    func viewModelRows() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        repository.emit([message("1", author: "bob", at: 1)])
        #expect(await eventually { model.rows.map(\.id) == ["1"] })
        let version = model.transcriptVersion
        var edited = message("1", author: "bob", at: 1)
        edited.text = "правка"
        repository.emit([edited])
        #expect(await eventually { model.rows.first?.message.text == "правка" })
        #expect(model.transcriptVersion == version)
        repository.emit([edited, message("2", author: "me", at: 2)])
        #expect(await eventually { model.rows.count == 2 })
        #expect(model.transcriptVersion == version + 1)
        model.deactivate()
    }
}
