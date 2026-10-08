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
    /// Сплошная страница истории с сервера вокруг сообщения `messageId` (серверный id) или,
    /// если задан `at`, вокруг этого момента: до `forward` новее и до `backward` старше, от
    /// старых к новым. Для перехода к сообщению далеко за окном ленты (цитата, закреп, поиск) и
    /// листания от краёв такого окна. В кэш не пишется: это не свежая история, и окно ленты,
    /// которое держит последние сообщения подряд, её не видит.
    func historyAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async throws(OrbitleError) -> [Message]
    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    func loadMore(chatId: String, before: Date?) async throws(OrbitleError) -> [Message]
    /// Самые свежие сообщения с сервера.
    func fetchLatest(chatId: String) async throws(OrbitleError)
    /// Свежая страница, когда пользователь открыл чат: в отличие от фоновых чтений, не ждёт
    /// паузы после `too.many.requests` — без неё экран чата пуст.
    func openLatest(chatId: String) async throws(OrbitleError)
    /// Оптимистичная отправка со статусом `sending`. `replyTo` — локальный или серверный id цитаты.
    func send(text: String, chatId: String, replyTo: String?) async throws(OrbitleError)
    /// Текст с разметкой, которую ставит само поле ввода (анимодзи из панели эмодзи).
    func send(text: String, chatId: String, replyTo: String?, formatting: [TextSpan]) async throws(OrbitleError)
    /// Правка текста и всей разметки (`MSG_EDIT` 67 несёт полный список, пустой снимает её).
    func edit(messageId: String, chatId: String, text: String, formatting: [TextSpan]) async throws(OrbitleError)
    /// Удалить выбранное одним запросом. Ответ — id, которые сервер не удалил (они остаются).
    func deleteSelection(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) -> [String]
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
    /// «Кем прочитано» (docs/readers.md): сначала отреагировавшие, затем прочитавшие, без себя
    /// и автора. Пусто, если в чате списка нет. Ошибка — только если не удалось ничего.
    func messageReaders(messageId: String) async throws(OrbitleError) -> [MessageReader]
    /// Есть ли в чате «Кем прочитано» — по сохранённой в ядре карточке, без запроса.
    func readersAvailable(chatId: String) async -> Bool
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
    public func openLatest(chatId: String) async throws(OrbitleError) {
        try await fetchLatest(chatId: chatId)
    }

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

    /// Источник без разметки при правке: уходит только текст.
    public func edit(messageId: String, chatId: String, text: String, formatting: [TextSpan]) async throws(OrbitleError) {
        try await edit(messageId: messageId, chatId: chatId, text: text)
    }

    /// Источник без ответа по каждому id: удалилось всё или ничего.
    public func deleteSelection(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) -> [String] {
        try await delete(messageIds: messageIds, chatId: chatId, forEveryone: forEveryone)
        return []
    }

    public func pin(chatId: String, messageId: String) async throws(OrbitleError) { throw .invalidRequest }
    public func schedule(chatId: String, text: String, sendAt: Date) async throws(OrbitleError) { throw .invalidRequest }
    public func scheduled(chatId: String) async throws(OrbitleError) -> [FoundMessage] { throw .invalidRequest }
    public func sendPoll(chatId: String, title: String, answers: [String]) async throws(OrbitleError) { throw .invalidRequest }
    public func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async throws(OrbitleError) { throw .invalidRequest }
    public func searchInChat(chatId: String, query: String) async throws(OrbitleError) -> [FoundMessage] { throw .invalidRequest }

    public func sharedHistory(chatId: String, limit: Int) async -> [Message] { [] }

    public func historyAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async throws(OrbitleError) -> [Message] {
        throw .invalidRequest
    }

    public func sharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> [Message]? {
        nil
    }

    public func syncReactions(chatId: String, messageIds: [String]) async -> Bool { true }

    public func reactionUsers(messageId: String) async throws(OrbitleError) -> [ReactionUser] {
        throw .invalidRequest
    }

    public func messageReaders(messageId: String) async throws(OrbitleError) -> [MessageReader] {
        throw .invalidRequest
    }

    public func readersAvailable(chatId: String) async -> Bool { false }

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
