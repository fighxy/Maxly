import Foundation
import OrbitleDomain

/// Комментарии постов через ядро: история (`CHAT_HISTORY` с `postId`) и отправка
/// (`MSG_SEND` с `postId`).
public struct CoreCommentsRepository: CommentsRepository {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(OrbitleError) -> [Message] {
        do {
            let page = try await core.loadComments(chatId: chatId, postId: postId, beforeMs: before?.unixMillis ?? 0, limit: limit)
            return page.map { Self.comment($0, postId: postId) }
        } catch {
            Log.warning(.messages, "Комментарии поста \(postId) не загрузились: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    public func send(text: String, chatId: String, postId: String) async throws(OrbitleError) -> Message {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw .invalidRequest }
        do {
            let sent = try await core.sendComment(chatId: chatId, postId: postId, text: body)
            return Self.comment(sent, postId: postId)
        } catch {
            Log.warning(.messages, "Комментарий к посту \(postId) не отправлен: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    public func counts(chatId: String, postIds: [String]) async throws(OrbitleError) -> [String: Int] {
        guard !postIds.isEmpty else { return [:] }
        do {
            return try await core.loadCommentCounts(chatId: chatId, postIds: postIds)
        } catch {
            Log.warning(.messages, "Счётчики комментариев не загрузились: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    public func setReaction(chatId: String, postId: String, commentId: String, emoji: String?) async throws(OrbitleError) -> ReactionUpdate? {
        guard Int64(commentId) != nil else { throw .rejected("Комментарий ещё не отправлен") }
        do {
            let json = try await core.setReaction(chatId: chatId, messageId: commentId, postId: postId, emoji: emoji ?? "")
            return MessageContentCodec.reactionUpdate(json)
        } catch {
            Log.warning(.messages, "Реакция на комментарий \(commentId) не изменена: \(error)")
            throw CoreMapping.apiError(error).orbitleError
        }
    }

    private static func comment(_ message: CoreMessage, postId: String) -> Message {
        var domain = CoreMapping.message(message).domain
        domain.content.threadOf = postId
        return domain
    }
}
