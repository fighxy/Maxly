import Foundation

/// Комментарии под постом канала. Живут на сервере, в локальную ленту чата не попадают.
public protocol CommentsRepository: Sendable {
    /// До `limit` комментариев строго старше `before` (самые новые, если `nil`), от старых к новым.
    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(OrbitleError) -> [Message]
    /// Отправляет комментарий и возвращает его в том виде, в каком его принял сервер.
    func send(text: String, chatId: String, postId: String) async throws(OrbitleError) -> Message
    /// Число комментариев под постами: id поста → число.
    func counts(chatId: String, postIds: [String]) async throws(OrbitleError) -> [String: Int]
}

public extension CommentsRepository {
    /// Источник без счётчиков: плашка покажет «Комментировать».
    func counts(chatId: String, postIds: [String]) async throws(OrbitleError) -> [String: Int] { [:] }
}
