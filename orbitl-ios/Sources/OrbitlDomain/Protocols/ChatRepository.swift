import Foundation

/// Список чатов. Сначала отдаёт кэш, потом обновляет его с сервера.
// TODO: architecture.md, «iOS-клиент», пункт 3 (кэш сразу, обновление в фоне).
public protocol ChatRepository: Sendable {
    func chats() -> AsyncStream<[Chat]>
    func refresh() async throws(OrbitlError)
}
