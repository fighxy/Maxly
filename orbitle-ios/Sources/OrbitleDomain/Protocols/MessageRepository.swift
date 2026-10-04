import Foundation

/// Сообщения чата. Исходящие пишутся оптимистично и уходят через очередь.
public protocol MessageRepository: Sendable {
    /// Сообщения чата от старых к новым в пределах показанного окна.
    func messages(chatId: String) -> AsyncStream<[Message]>
    /// Сохранённая история чата с вложениями и ссылками, от старых к новым, — для общих медиа
    /// профиля. Только кэш устройства, без сети.
    func sharedHistory(chatId: String, limit: Int) async -> [Message]
    /// Сообщения чата с вложениями `types` прямо с сервера, вокруг сообщения `anchorId`
    /// (серверный id): до `forward` новее и до `backward` старше. В кэш не пишутся — это не
    /// сплошная история. `nil` — сервер не ответил.
    func sharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> [Message]?
    /// Расширить окно на страницу, при необходимости догрузив историю с сервера.
    func loadOlder(chatId: String) async throws(OrbitleError)
    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    func loadMore(chatId: String, before: Date?) async throws(OrbitleError) -> [Message]
    /// Самые свежие сообщения с сервера.
    func fetchLatest(chatId: String) async throws(OrbitleError)
    /// Оптимистичная отправка со статусом `sending`. `replyTo` — локальный или серверный id цитаты.
    func send(text: String, chatId: String, replyTo: String?) async throws(OrbitleError)
    /// Текст с разметкой, которую ставит само поле ввода (анимодзи из панели эмодзи).
    func send(text: String, chatId: String, replyTo: String?, formatting: [TextSpan]) async throws(OrbitleError)
    /// Повторная отправка сообщения со статусом `failed`.
    func retry(messageId: String) async throws(OrbitleError)
    /// Поставить реакцию `emoji` или снять её, если она уже своя. Другая своя реакция
    /// заменяется: у аккаунта одна реакция на сообщение. Изменение видно сразу, при ошибке
    /// сервера оно откатывается и ошибка пробрасывается.
    func toggleReaction(messageId: String, emoji: String) async throws(OrbitleError)
    /// Обновить с сервера реакции показанных сообщений чата.
    func refreshReactions(chatId: String) async
    /// Реакции этих сообщений отдельным запросом: в истории канала их нет, своя реакция
    /// с другого устройства в пушах не видна.
    func syncReactions(chatId: String, messageIds: [String]) async -> Bool
    /// Кто поставил реакции на сообщение.
    func reactionUsers(messageId: String) async throws(OrbitleError) -> [ReactionUser]
    /// Эмодзи, которые сервер предлагает для реакций, в его порядке. Пусто, если каталог
    /// не загрузился.
    func reactionCatalog() async -> [String]
    /// Комментарии поста, от старых к новым. В общую ленту чата они не входят.
    func comments(chatId: String, postId: String) -> AsyncStream<[Message]>
    /// Комментарий остаётся на устройстве: у фасада нет отдельной отправки в тред.
    func sendComment(text: String, chatId: String, postId: String) async throws(OrbitleError)
    /// Запомнить скачанный файл у вложения, не стирая остальной фрагмент.
    func noteDownloaded(messageId: String, attachmentId: String, localPath: String) async
    /// Расшифровать голосовое `attachmentId` сообщения. `true` — текст уже записан в сообщение,
    /// `false` — сервер ещё работает, текст придёт пушем и тоже ляжет в сообщение.
    func transcribe(messageId: String, attachmentId: String) async throws(OrbitleError) -> Bool
    /// Запомнить счётчики комментариев постов (серверный id → число): при следующем открытии
    /// пузырь сразу ляжет с полосой комментариев, а не вырастет после запроса.
    func noteCommentCounts(chatId: String, counts: [String: Int]) async
    /// Удалить сообщения: `forEveryone` — у всех участников, иначе только у себя.
    /// Неотправленные (без серверного id) удаляются только на устройстве.
    func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError)
    /// Заменить текст своего отправленного сообщения.
    func edit(messageId: String, chatId: String, text: String) async throws(OrbitleError)
    /// Переслать сообщение `messageId` из `chatId` в чат `targetChatId`.
    func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(OrbitleError)
    /// Одно сообщение с вложениями и подписью `caption` (пустая — без подписи). Пузырь со
    /// статусом `sending` появляется сразу, загрузка идёт в фоне: ход виден в `uploadProgress`,
    /// итог — сменой статуса. Ошибка бросается, только если сообщение не удалось записать.
    func sendAttachments(_ drafts: [AttachmentDraft], caption: String, chatId: String, replyTo: String?) async throws(OrbitleError)
    /// Остановить загрузку и убрать неотправленное сообщение с вложениями.
    func cancelUpload(messageId: String) async
    /// Ход загрузок: локальный id сообщения → доля 0…1. Сразу при подписке и после каждого шага.
    func uploadProgress() -> AsyncStream<[String: Double]>
    /// Закрепить сообщение. `messageId` `0` снимает закреп.
    func pin(chatId: String, messageId: String) async throws(OrbitleError)
    func schedule(chatId: String, text: String, sendAt: Date) async throws(OrbitleError)
    func scheduled(chatId: String) async throws(OrbitleError) -> [FoundMessage]
    func sendPoll(chatId: String, title: String, answers: [String]) async throws(OrbitleError)
    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws(OrbitleError)
    func searchInChat(chatId: String, query: String) async throws(OrbitleError) -> [FoundMessage]
}

extension MessageRepository {
    /// Отправка без цитаты.
    public func send(text: String, chatId: String) async throws(OrbitleError) {
        try await send(text: text, chatId: chatId, replyTo: nil)
    }

    public func toggleReaction(messageId: String, emoji: String) async throws(OrbitleError) {
        throw .invalidRequest
    }

    public func refreshReactions(chatId: String) async {}

    public func send(text: String, chatId: String, replyTo: String?, formatting: [TextSpan]) async throws(OrbitleError) {
        try await send(text: text, chatId: chatId, replyTo: replyTo)
    }

    public func pin(chatId: String, messageId: String) async throws(OrbitleError) { throw .invalidRequest }
    public func schedule(chatId: String, text: String, sendAt: Date) async throws(OrbitleError) { throw .invalidRequest }
    public func scheduled(chatId: String) async throws(OrbitleError) -> [FoundMessage] { throw .invalidRequest }
    public func sendPoll(chatId: String, title: String, answers: [String]) async throws(OrbitleError) { throw .invalidRequest }
    public func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws(OrbitleError) { throw .invalidRequest }
    public func searchInChat(chatId: String, query: String) async throws(OrbitleError) -> [FoundMessage] { throw .invalidRequest }

    public func sharedHistory(chatId: String, limit: Int) async -> [Message] { [] }

    public func sharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> [Message]? {
        nil
    }

    public func syncReactions(chatId: String, messageIds: [String]) async -> Bool { true }

    public func reactionUsers(messageId: String) async throws(OrbitleError) -> [ReactionUser] {
        throw .invalidRequest
    }

    public func reactionCatalog() async -> [String] { [] }

    public func comments(chatId: String, postId: String) -> AsyncStream<[Message]> {
        AsyncStream { $0.finish() }
    }

    public func sendComment(text: String, chatId: String, postId: String) async throws(OrbitleError) {}

    public func noteDownloaded(messageId: String, attachmentId: String, localPath: String) async {}

    public func transcribe(messageId: String, attachmentId: String) async throws(OrbitleError) -> Bool {
        throw .invalidRequest
    }

    public func noteCommentCounts(chatId: String, counts: [String: Int]) async {}

    public func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) {
        throw .invalidRequest
    }

    public func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(OrbitleError) {
        throw .invalidRequest
    }

    public func edit(messageId: String, chatId: String, text: String) async throws(OrbitleError) {
        throw .invalidRequest
    }

    public func sendAttachments(_ drafts: [AttachmentDraft], caption: String, chatId: String, replyTo: String?) async throws(OrbitleError) {
        throw .invalidRequest
    }

    public func cancelUpload(messageId: String) async {}

    public func uploadProgress() -> AsyncStream<[String: Double]> {
        AsyncStream { $0.finish() }
    }
}
