import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private func photo(_ n: Int) -> AttachmentDraft {
    AttachmentDraft(kind: .photo, path: "/p/\(n).jpg", fileName: "image.jpg")
}

private let video = AttachmentDraft(kind: .video, path: "/v.mp4", fileName: "video.mp4")
private let file = AttachmentDraft(kind: .file, path: "/f.pdf", fileName: "f.pdf")
private let card = AttachmentDraft.contact(id: "42", name: "Мария")

@Suite("Вложения: деление на сообщения")
struct AttachmentPlannerTests {
    @Test("Фото подряд — одно сообщение до 10, подпись с первым")
    func photos() {
        let plan = AttachmentBatchPlanner.plan((1...12).map(photo), caption: "  Отпуск ")
        #expect(plan.batches.map(\.drafts.count) == [10, 2])
        #expect(plan.batches.map(\.caption) == ["Отпуск", ""])
        #expect(plan.trailingText.isEmpty)
    }

    @Test("Видео, файл и контакт — по одному, порядок выбора сохраняется")
    func mixed() {
        let plan = AttachmentBatchPlanner.plan([photo(1), photo(2), video, photo(3), file, card], caption: "")
        #expect(plan.batches.map(\.drafts) == [[photo(1), photo(2)], [video], [photo(3)], [file], [card]])
    }

    @Test("Подпись не достаётся контакту; одни контакты — подпись отдельным текстом")
    func captionPlacement() {
        let first = AttachmentBatchPlanner.plan([card, video], caption: "смотри")
        #expect(first.batches.map(\.caption) == ["", "смотри"])
        let contacts = AttachmentBatchPlanner.plan([card, .contact(id: "43", name: "Иван")], caption: "вот")
        #expect(contacts.batches.count == 2)
        #expect(contacts.batches.allSatisfy { $0.caption.isEmpty })
        #expect(contacts.trailingText == "вот")
        #expect(AttachmentBatchPlanner.plan([], caption: "x").batches.isEmpty)
    }
}

@Suite("Вложения: лист")
@MainActor
struct AttachmentSheetTests {
    @Test("Выбор нумеруется по порядку, снятие сдвигает номера, лимит")
    func selection() {
        let model = AttachmentSheetModel()
        model.toggle("a")
        model.toggle("b")
        model.toggle("c")
        #expect(model.number(of: "c") == 3)
        model.toggle("a")
        #expect(model.number(of: "a") == nil)
        #expect(model.number(of: "b") == 1)
        #expect(model.number(of: "c") == 2)
        #expect(model.sendTitle == "Отправить (2)")
        for index in 0..<AttachmentSheetModel.selectionLimit { model.toggle("x\(index)") }
        #expect(model.selection.count == AttachmentSheetModel.selectionLimit)
        #expect(model.limitReached)
        model.clearSelection()
        #expect(!model.hasSelection)
        #expect(model.sendTitle == "Отправить")
    }

    @Test("Поиск контакта: регистр, «ё» как «е», номер по цифрам")
    func contactSearch() {
        let model = AttachmentSheetModel(contacts: [
            Contact(id: "1", firstName: "Семён", lastName: "Орлов", phone: "+7 999 111-22-33"),
            Contact(id: "2", firstName: "анна", phone: "+79990000000"),
            Contact(id: "3", firstName: "Борис"),
        ])
        #expect(model.filteredContacts.map(\.id) == ["2", "3", "1"])
        model.contactQuery = "СЕМЕН"
        #expect(model.filteredContacts.map(\.id) == ["1"])
        model.contactQuery = "111 22"
        #expect(model.filteredContacts.map(\.id) == ["1"])
        model.contactQuery = "зоя"
        #expect(model.filteredContacts.isEmpty)
        let draft = model.contactDraft(Contact(id: "2", firstName: "анна", phone: "+79990000000"))
        #expect(draft == .contact(id: "2", name: "анна", phone: "+79990000000"))
    }

    @Test("Геопозиция и опрос пока недоступны")
    func tabs() {
        #expect(AttachmentSheetModel.Tab.allCases.filter(\.isAvailable) == [.gallery, .file, .contact])
        #expect(AttachmentSheetModel.Tab.allCases.map(\.title) == ["Галерея", "Файл", "Геопозиция", "Опрос", "Контакт"])
    }
}

@Suite("Вложения: экран чата")
@MainActor
struct AttachmentChatTests {
    @Test("Набор уходит сообщениями, цитата с первым, подпись одним текстом после контактов")
    func send() async throws {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.beginReply(to: Message(id: "m1", serverId: "m1", chatId: "c", authorId: "bob", text: "привет", timestamp: .now, status: .sent))
        await model.sendAttachments([photo(1), video], caption: "подпись")
        let sends = await repository.attachmentSends
        #expect(sends.map(\.drafts) == [[photo(1)], [video]])
        #expect(sends.map(\.caption) == ["подпись", ""])
        #expect(sends.map(\.replyTo) == ["m1", nil])
        #expect(model.replyTarget == nil)

        await model.sendAttachments([card], caption: "это он")
        #expect(await repository.sent == ["это он"])
    }

    @Test("Ошибка отправки показывается")
    func failure() async throws {
        let repository = FakeMessageRepository()
        await repository.set(attachmentError: .storageError)
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.sendAttachments([file], caption: "")
        #expect(model.errorMessage != nil)
    }

    @Test("Ход загрузки доходит до экрана, отмена уходит в репозиторий")
    func progressAndCancel() async throws {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        #expect(await eventually { await repository.progressSubscribers == 1 })
        await repository.publish(progress: ["local-1": 0.4])
        #expect(await eventually { model.uploadProgress["local-1"] == 0.4 })
        let message = Message(id: "local-1", chatId: "c", authorId: "me", text: "", timestamp: .now, status: .sending)
        #expect(model.uploadFraction(of: message) == 0.4)
        await model.cancelUpload(message)
        #expect(await repository.cancelledUploads == ["local-1"])
        model.deactivate()
    }

    @Test("Ошибка загрузки от сервера видна в чате, чужие чаты её не показывают")
    func uploadFailureNotice() async throws {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        #expect(await eventually { await repository.failureSubscribers == 1 })
        await repository.publish(failure: UploadFailure(chatId: "other", messageId: "local-0", text: "file.too.big"))
        await repository.publish(failure: UploadFailure(chatId: "c", messageId: "local-1", text: " upload.failed "))
        #expect(await eventually { model.notice == "Вложение не отправлено: upload.failed" })
        await repository.publish(failure: UploadFailure(chatId: "c", messageId: "local-2", text: ""))
        #expect(await eventually { model.notice == "Вложение не отправлено" })
        model.deactivate()
    }
}
