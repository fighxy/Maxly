import Foundation

/// Комментарии под постом канала. Живут на сервере, в локальную ленту чата не попадают.
public protocol CommentsRepository: Sendable {
    /// До `limit` комментариев строго старше `before` (самые новые, если `nil`), от старых к новым.
    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(MaxlyError) -> [Message]
    /// Отправляет комментарий и возвращает его в том виде, в каком его принял сервер.
    func send(text: String, chatId: String, postId: String) async throws(MaxlyError) -> Message
    /// Число комментариев под постами: id поста → число.
    func counts(chatId: String, postIds: [String]) async throws(MaxlyError) -> [String: Int]
    /// Поставить свою реакцию `emoji` на комментарий `commentId` или снять её (`nil`).
    /// Ответ — реакции, которые вернул сервер, или `nil`, если он их не прислал.
    func setReaction(chatId: String, postId: String, commentId: String, emoji: String?) async throws(MaxlyError) -> ReactionUpdate?
}

public extension CommentsRepository {
    /// Источник без счётчиков: плашка покажет «Комментировать».
    func counts(chatId: String, postIds: [String]) async throws(MaxlyError) -> [String: Int] { [:] }
    /// Источник без реакций: изменение откатывается.
    func setReaction(chatId: String, postId: String, commentId: String, emoji: String?) async throws(MaxlyError) -> ReactionUpdate? {
        throw .invalidRequest
    }
}
