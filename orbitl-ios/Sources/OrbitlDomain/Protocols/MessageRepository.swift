import Foundation

/// Сообщения чата. Исходящие пишутся оптимистично и уходят через очередь.
public protocol MessageRepository: Sendable {
    /// Сообщения чата от старых к новым в пределах показанного окна.
    func messages(chatId: String) -> AsyncStream<[Message]>
    /// Расширить окно на страницу, при необходимости догрузив историю с сервера.
    func loadOlder(chatId: String) async throws(OrbitlError)
    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    func loadMore(chatId: String, before: Date?) async throws(OrbitlError) -> [Message]
    /// Самые свежие сообщения с сервера.
    func fetchLatest(chatId: String) async throws(OrbitlError)
    /// Оптимистичная отправка со статусом `sending`.
    func send(text: String, chatId: String) async throws(OrbitlError)
    /// Повторная отправка сообщения со статусом `failed`.
    func retry(messageId: String) async throws(OrbitlError)
}
