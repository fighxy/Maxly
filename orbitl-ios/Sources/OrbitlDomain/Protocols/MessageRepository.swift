import Foundation

/// Сообщения чата. Исходящие пишутся оптимистично и уходят через очередь.
// TODO: architecture.md, «Синхронизация с сервером», «Ошибки и офлайн».
public protocol MessageRepository: Sendable {
    func messages(chatId: String) -> AsyncStream<[Message]>
    func loadOlder(chatId: String) async throws(OrbitlError)
    func send(text: String, chatId: String) async throws(OrbitlError)
}
