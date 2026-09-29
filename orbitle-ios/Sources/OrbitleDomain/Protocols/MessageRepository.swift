import Foundation

/// Сообщения чата. Исходящие пишутся оптимистично и уходят через очередь.
public protocol MessageRepository: Sendable {
    /// Сообщения чата от старых к новым в пределах показанного окна.
    func messages(chatId: String) -> AsyncStream<[Message]>
    /// Расширить окно на страницу, при необходимости догрузив историю с сервера.
    func loadOlder(chatId: String) async throws(OrbitleError)
    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    func loadMore(chatId: String, before: Date?) async throws(OrbitleError) -> [Message]
    /// Самые свежие сообщения с сервера.
    func fetchLatest(chatId: String) async throws(OrbitleError)
    /// Оптимистичная отправка со статусом `sending`. `replyTo` — локальный или серверный id цитаты.
    func send(text: String, chatId: String, replyTo: String?) async throws(OrbitleError)
    /// Повторная отправка сообщения со статусом `failed`.
    func retry(messageId: String) async throws(OrbitleError)
    /// Поставить или снять свою реакцию. На сервер уходит только когда фасад это умеет.
    func setReaction(messageId: String, emoji: String) async throws(OrbitleError)
    /// Комментарии поста, от старых к новым. В общую ленту чата они не входят.
    func comments(chatId: String, postId: String) -> AsyncStream<[Message]>
    /// Комментарий остаётся на устройстве: у фасада нет отдельной отправки в тред.
    func sendComment(text: String, chatId: String, postId: String) async throws(OrbitleError)
    /// Запомнить скачанный файл у вложения, не стирая остальной фрагмент.
    func noteDownloaded(messageId: String, attachmentId: String, localPath: String) async
}

extension MessageRepository {
    /// Отправка без цитаты.
    public func send(text: String, chatId: String) async throws(OrbitleError) {
        try await send(text: text, chatId: chatId, replyTo: nil)
    }

    public func setReaction(messageId: String, emoji: String) async throws(OrbitleError) {}

    public func comments(chatId: String, postId: String) -> AsyncStream<[Message]> {
        AsyncStream { $0.finish() }
    }

    public func sendComment(text: String, chatId: String, postId: String) async throws(OrbitleError) {}

    public func noteDownloaded(messageId: String, attachmentId: String, localPath: String) async {}
}
