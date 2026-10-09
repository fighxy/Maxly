import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

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
        await repository.set(latestError: .server(code: "chat.not.found", text: nil))
        let model = ChatViewModel(chatId: "13", currentUserId: "10", messages: repository, isNewDialog: true)
        await model.loadLatest()
        #expect(model.error == nil)
        #expect(model.emptyHint != nil)
        // Без сети ошибка по-прежнему видна.
        await repository.set(latestError: .networkUnavailable)
        await model.loadLatest()
        #expect(model.error == .networkUnavailable)

        let existing = ChatViewModel(chatId: "13", currentUserId: "10", messages: repository)
        await repository.set(latestError: .server(code: "x", text: nil))
        await existing.loadLatest()
        #expect(existing.error == .server(code: "x", text: nil))
        #expect(existing.emptyHint == nil)
    }

    @Test("too.many.requests: без красной строки, пустой экран объясняет паузу")
    func rateLimitOnEmptyScreen() async {
        let repository = FakeMessageRepository()
        await repository.set(latestError: .server(code: OrbitleError.rateLimitCode, text: nil))
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.loadLatest()
        #expect(model.error == nil)
        #expect(model.historyError?.userMessage == "Сервер просит подождать: слишком много запросов")
        model.deactivate()
    }

    @Test("Ошибка отправки возвращает и черновик, и цитату")
    func sendRestoresReply() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let target = Message(id: "p", chatId: "c", authorId: "bob", text: "Исходное", timestamp: .now, status: .sent)
        model.beginReply(to: target)
        model.draft = "Ответ"
        await repository.set(sendError: .storageError)
        await model.send()
        #expect(model.draft == "Ответ")
        #expect(model.replyTarget?.id == "p")
        #expect(await repository.sent == ["Ответ"])
        #expect(await repository.replyIds == ["p"])
    }

    @Test("Фото и видео открываются отдельными кадрами, постер не подменяет ролик")
    func presentMedia() throws {
        let photo = PhotoContent(id: "p", url: URL(string: "https://cdn.example/p.jpg"), width: 800, height: 600)
        let video = VideoContent(
            id: "v",
            url: URL(string: "https://cdn.example/v.mp4"),
            posterURL: URL(string: "https://cdn.example/t.jpg"),
            durationMs: 3200
        )
        let posterOnly = VideoContent(id: "poster", url: nil, posterURL: URL(string: "https://cdn.example/only.jpg"))
        let message = Message(
            id: "m",
            chatId: "c",
            authorId: "bob",
            text: "",
            timestamp: .now,
            status: .sent,
            content: MessageContent(attachments: [.photo(photo), .video(video), .video(posterOnly)])
        )
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        model.presentMedia(message, startId: "v")
        let slides = try #require(model.viewer?.slides)
        #expect(model.viewer?.id == "v")
        #expect(slides.map(\.id) == ["p", "v", "poster"])
        #expect(slides[1].stillURL == video.posterURL)
        #expect(slides[1].playURL == video.url)
        #expect(slides[1].isVideo == true)
        #expect(slides[2].isVideo == false)
        #expect(slides[2].playURL == nil)
    }

    @Test("Голос без файла и без кэша помечает пузырь ошибкой")
    func voiceFailsWithoutFile() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let voice = VoiceContent(id: "a", url: URL(string: "https://cdn.example/a.ogg"), durationMs: 3200)
        let message = Message(
            id: "m",
            chatId: "c",
            authorId: "bob",
            text: "",
            timestamp: .now,
            status: .sent,
            content: MessageContent(attachments: [.voice(voice)])
        )
        model.toggleVoice(message)
        #expect(await eventually { model.voicePhase(for: "a") == .failed })
    }
}
