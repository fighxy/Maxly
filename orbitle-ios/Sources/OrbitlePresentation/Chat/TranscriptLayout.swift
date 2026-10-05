import Foundation
import OrbitleDomain

/// Строка ленты чата: сообщение и всё, что зависит от соседей, посчитанное один раз при
/// смене ленты, как готовая раскладка ячеек. Экран не пересчитывает склейку, разделители
/// дней и подписи автора при каждой перерисовке и сравнивает строки целиком: пузырь
/// перерисовывается, только если поменялась его строка.
public struct TranscriptRow: Identifiable, Equatable, Sendable {
    public var message: Message
    /// «Сегодня», «12 сентября» — разделитель дня над сообщением; `nil`, если день тот же.
    public var dayTitle: String?
    public var group: BubbleGroup
    /// Имя автора над пузырём (в группах): чужое сообщение после другого автора.
    public var showsAuthorName: Bool
    /// Аватар автора у последнего пузыря подряд (в группах).
    public var showsAuthorAvatar: Bool
    public var isOutgoing: Bool
    /// Над сообщением «Непрочитанные сообщения»: первое непрочитанное при открытии чата.
    public var startsUnread: Bool = false

    public var id: String { message.id }
}

public enum TranscriptLayout {
    public static func rows(_ messages: [Message], currentUserId: String, unreadAnchorId: String? = nil, now: Date = Date()) -> [TranscriptRow] {
        messages.indices.map { index in
            let message = messages[index]
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let outgoing = !currentUserId.isEmpty && message.authorId == currentUserId
            let startsDay = ChatContentFormat.startsDay(message.timestamp, after: previous?.timestamp)
            return TranscriptRow(
                message: message,
                dayTitle: startsDay ? ChatContentFormat.dayTitle(message.timestamp, now: now) : nil,
                group: ChatContentFormat.group(
                    authorId: message.authorId,
                    date: message.timestamp,
                    previous: previous.map { (authorId: $0.authorId, date: $0.timestamp) },
                    next: next.map { (authorId: $0.authorId, date: $0.timestamp) }
                ),
                showsAuthorName: ChatContentFormat.showsAuthorName(
                    outgoing: outgoing,
                    authorName: message.authorName,
                    authorId: message.authorId,
                    previousAuthorId: previous?.authorId
                ),
                showsAuthorAvatar: ChatContentFormat.showsAuthorAvatar(
                    outgoing: outgoing,
                    authorId: message.authorId,
                    nextAuthorId: next?.authorId
                ),
                isOutgoing: outgoing,
                startsUnread: unreadAnchorId != nil && message.id == unreadAnchorId
            )
        }
    }

    /// Первое непрочитанное из `unread` последних чужих сообщений (служебные и свои не
    /// считаются, как и в счётчике сервера). Если ленты не хватает, а она уже сверена с
    /// сервером (`complete`), — самое старое чужое сообщение ленты; иначе `nil`, ждём историю.
    public static func unreadAnchor(_ messages: [Message], unread: Int, currentUserId: String, complete: Bool) -> String? {
        guard unread > 0 else { return nil }
        var seen = 0
        var oldest: String?
        for message in messages.reversed() where message.authorId != currentUserId && message.content.pin == nil {
            seen += 1
            oldest = message.id
            if seen == unread { return message.id }
        }
        return complete ? oldest : nil
    }
}
