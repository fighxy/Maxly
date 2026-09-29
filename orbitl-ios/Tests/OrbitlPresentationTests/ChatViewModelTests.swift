import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlPresentation

@Suite("Экран чата")
@MainActor
struct ChatViewModelTests {
    @Test("Отправка обрезает пробелы и очищает черновик")
    func send() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.draft = "   "
        #expect(!model.canSend)
        await model.send()
        #expect(await repository.sent.isEmpty)
        model.draft = "  Привет \n"
        await model.send()
        #expect(await repository.sent == ["Привет"])
        #expect(model.draft == "")
        #expect(model.error == nil)
    }

    @Test("Ошибка отправки возвращает черновик, отмена не показывается")
    func sendError() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await repository.set(sendError: .storageError)
        model.draft = "Текст"
        await model.send()
        #expect(model.draft == "Текст")
        #expect(model.errorMessage == "Не удалось сохранить данные на устройстве")
        await repository.set(sendError: .cancelled)
        await model.send()
        #expect(model.errorMessage == "Не удалось сохранить данные на устройстве")
    }

    @Test("Своё сообщение определяется по автору, без id все входящие")
    func outgoing() {
        let message = Message(id: "1", chatId: "c", authorId: "me", text: "x", timestamp: .now, status: .sent)
        #expect(ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository()).isOutgoing(message))
        #expect(!ChatViewModel(chatId: "c", currentUserId: "", messages: FakeMessageRepository()).isOutgoing(message))
    }

    @Test("Новый диалог: пустая история не ошибка, экран предлагает первое сообщение")
    func newDialog() async {
        let repository = FakeMessageRepository()
        await repository.set(latestError: .server(code: "chat.not.found"))
        let model = ChatViewModel(chatId: "13", currentUserId: "10", messages: repository, isNewDialog: true)
        await model.loadLatest()
        #expect(model.error == nil)
        #expect(model.emptyHint != nil)
        // Без сети ошибка по-прежнему видна.
        await repository.set(latestError: .networkUnavailable)
        await model.loadLatest()
        #expect(model.error == .networkUnavailable)

        let existing = ChatViewModel(chatId: "13", currentUserId: "10", messages: repository)
        await repository.set(latestError: .server(code: "x"))
        await existing.loadLatest()
        #expect(existing.error == .server(code: "x"))
        #expect(existing.emptyHint == nil)
    }
}
