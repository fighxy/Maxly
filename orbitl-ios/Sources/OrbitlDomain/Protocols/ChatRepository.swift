import Foundation

/// Список чатов. Сначала отдаёт кэш, потом обновляет его с сервера.
public protocol ChatRepository: Sendable {
    /// Чаты по убыванию `updatedAt`. Первое значение сразу из кэша.
    func chats() -> AsyncStream<[Chat]>
    /// Обновить список с сервера.
    func refresh() async throws(OrbitlError)
    /// Обновить один чат с сервера.
    func refresh(chatId: String) async throws(OrbitlError)
    /// Сбросить непрочитанные локально и на сервере. При ошибке сервера
    /// локальное изменение остаётся, а ошибка пробрасывается.
    func markAsRead(chatId: String) async throws(OrbitlError)
}
