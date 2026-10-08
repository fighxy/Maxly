import Foundation

/// Отправка «я печатаю» (`MSG_TYPING` 65, ответа нет). Подключается, когда мост ядра
/// (`MaxIos`) отдаст `sendTyping`; до этого приложение держит заглушку, которая ничего не шлёт.
public protocol TypingSender: Sendable {
    /// `postId` — комментарий под постом канала, иначе `nil`.
    func sendTyping(chatId: String, type: String, postId: String?) async throws
}

/// Заглушка отправителя: мост ядра ещё не умеет 65, поэтому ничего не уходит.
public struct SilentTypingSender: TypingSender {
    public init() {}

    public func sendTyping(chatId: String, type: String, postId: String?) async throws {}
}
