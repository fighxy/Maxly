import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Сообщение с серверным id `id` и временем `id` секунд.
private func message(_ id: Int) -> Message {
    Message(id: "\(id)", serverId: "\(id)", chatId: "c", authorId: "bob", text: "m\(id)",
            timestamp: Date(timeIntervalSince1970: Double(id)), status: .sent)
}

@Suite("Разделитель непрочитанных по своей позиции")
@MainActor
struct OwnReadMarkDividerTests {
    private func opened(unread: Int, ownReadMark: Int64) async -> ChatViewModel {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.noteUnreadOnOpen(unread, ownReadMark: ownReadMark)
        await model.loadLatest()
        model.activate()
        repository.emit((1...5).map { message($0) })
        _ = await eventually { model.messages.count == 5 }
        return model
    }

    @Test("Своя позиция новее счётчика сервера (отметки скрыты) — разделитель за ней")
    func followsOwnMark() async {
        // Счётчик говорит «3 непрочитанных» (с 3-го), а на устройстве прочитано до 4-го.
        let model = await opened(unread: 3, ownReadMark: 4_000)
        #expect(await eventually { model.unreadAnchorId != nil })
        #expect(model.unreadAnchorId == "5")
        model.deactivate()
    }

    @Test("Своей позиции нет — разделитель по счётчику непрочитанных")
    func byCountWithoutMark() async {
        let model = await opened(unread: 3, ownReadMark: 0)
        #expect(await eventually { model.unreadAnchorId != nil })
        #expect(model.unreadAnchorId == "3")
        model.deactivate()
    }
}
