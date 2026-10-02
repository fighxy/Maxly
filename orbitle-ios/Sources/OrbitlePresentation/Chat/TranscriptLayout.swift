import Foundation
import OrbitleDomain

/// Строка ленты чата: сообщение и всё, что зависит от соседей, посчитанное один раз при
/// смене ленты, как раскладка ячеек в Telegram. Экран не пересчитывает склейку, разделители
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

    public var id: String { message.id }
}

public enum TranscriptLayout {
    public static func rows(_ messages: [Message], currentUserId: String, now: Date = Date()) -> [TranscriptRow] {
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
                isOutgoing: outgoing
            )
        }
    }
}
