import Foundation
import MaxlyDomain

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
    /// Фото или видео сообщения, на которое этот ответ, если оно есть в ленте: миниатюра в цитате.
    public var replyMedia: ChatAttachment? = nil
    /// Автор сообщения, на которое этот ответ, если оно есть в ленте: «Вы» или его имя. Сервер
    /// часто не присылает имя в самой цитате, и без ленты в ней было бы «Сообщение».
    public var replyAuthor: String? = nil
    /// Показывать кнопки бота под сообщением. В чате с ботом — только у его последнего меню:
    /// каждое нажатие приносит новое, и прежние копились бы столбиком.
    public var showsKeyboard: Bool = true

    public var id: String { message.id }
}

public enum TranscriptLayout {
    /// `latestKeyboardOnly` — чат с ботом: кнопки остаются только у последнего сообщения с
    /// кнопками от того же автора.
    public static func rows(
        _ messages: [Message],
        currentUserId: String,
        unreadAnchorId: String? = nil,
        latestKeyboardOnly: Bool = false,
        now: Date = Date()
    ) -> [TranscriptRow] {
        let replied = repliedMessages(messages, currentUserId: currentUserId)
        let keyboards = latestKeyboardOnly ? latestKeyboards(messages) : nil
        return messages.indices.map { index in
            let message = messages[index]
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let outgoing = !currentUserId.isEmpty && message.authorId == currentUserId
            let startsDay = ChatContentFormat.startsDay(message.timestamp, after: previous?.timestamp)
            let startsUnread = unreadAnchorId != nil && message.id == unreadAnchorId
            let service = message.content.isService
            // Разделитель и служебная строка разрывают серию с обеих сторон.
            // Имя, аватар и углы используют одни и те же границы, включая паузу по времени.
            let previousInGroup = !service && !startsUnread && previous?.content.isService != true ? previous : nil
            let nextInGroup = !service && next?.content.isService != true && next?.id != unreadAnchorId ? next : nil
            let group = ChatContentFormat.group(
                authorId: message.authorId,
                date: message.timestamp,
                previous: previousInGroup.map { (authorId: $0.authorId, date: $0.timestamp) },
                next: nextInGroup.map { (authorId: $0.authorId, date: $0.timestamp) }
            )
            return TranscriptRow(
                message: message,
                dayTitle: startsDay ? ChatContentFormat.dayTitle(message.timestamp, now: now) : nil,
                group: group,
                showsAuthorName: !service && !outgoing && !group.joinsPrevious
                    && !message.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                showsAuthorAvatar: !service && !outgoing && !group.joinsNext,
                isOutgoing: outgoing,
                startsUnread: startsUnread,
                replyMedia: message.content.reply.flatMap { replied[$0.messageId]?.media },
                replyAuthor: message.content.reply.flatMap { replied[$0.messageId]?.author },
                showsKeyboard: keyboards.map { message.content.keyboard == nil || $0.contains(message.id) } ?? true
            )
        }
    }

    /// Сообщение из ленты, на которое есть ответ: первое фото или видео и автор.
    struct Replied: Equatable {
        var media: ChatAttachment?
        var author: String?
    }

    /// Сообщения, на которые в ленте есть ответы, по `id` и `serverId`. Пусто, если ответов
    /// нет: ленту без них не перебираем второй раз.
    static func repliedMessages(_ messages: [Message], currentUserId: String) -> [String: Replied] {
        let targets = Set(messages.compactMap { $0.content.reply?.messageId })
        guard !targets.isEmpty else { return [:] }
        var replied: [String: Replied] = [:]
        for message in messages {
            let keys = [message.id, message.serverId].compactMap { $0 }.filter(targets.contains)
            guard !keys.isEmpty else { continue }
            let name = message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            let own = !currentUserId.isEmpty && message.authorId == currentUserId
            let info = Replied(media: message.content.visuals.first, author: own ? "Вы" : (name.isEmpty ? nil : name))
            for key in keys { replied[key] = info }
        }
        return replied
    }

    /// Сообщения, чьи кнопки видны: у каждого автора — последнее сообщение с кнопками.
    static func latestKeyboards(_ messages: [Message]) -> Set<String> {
        var seenAuthors = Set<String>()
        var shown = Set<String>()
        for message in messages.reversed() where message.content.keyboard != nil {
            if seenAuthors.insert(message.authorId).inserted { shown.insert(message.id) }
        }
        return shown
    }

    /// Первое непрочитанное по своей отметке прочтения `readMark` (мс, `OwnReadMark`): первое
    /// чужое сообщение новее неё. Отметка учитывается, только когда лента до неё дотягивается
    /// (в ней есть сообщение с сервера не новее отметки), иначе граница не видна. Без отметки,
    /// без такой ленты или без чужого новее — по счётчику `unread` (`unreadAnchor`). Без
    /// непрочитанных разделителя нет.
    public static func firstUnread(_ messages: [Message], readMark: Int64, unread: Int, currentUserId: String, complete: Bool) -> String? {
        guard unread > 0 else { return nil }
        if readMark > 0, messages.contains(where: { $0.status == .sent && ReadMark.time(of: $0) <= readMark }),
           let first = messages.first(where: {
               $0.status == .sent && $0.authorId != currentUserId && !$0.content.isService && ReadMark.time(of: $0) > readMark
           }) {
            return first.id
        }
        return unreadAnchor(messages, unread: unread, currentUserId: currentUserId, complete: complete)
    }

    /// Первое непрочитанное из `unread` последних чужих сообщений (служебные и свои не
    /// считаются, как и в счётчике сервера). Если ленты не хватает, а она уже сверена с
    /// сервером (`complete`), — самое старое чужое сообщение ленты; иначе `nil`, ждём историю.
    public static func unreadAnchor(_ messages: [Message], unread: Int, currentUserId: String, complete: Bool) -> String? {
        guard unread > 0 else { return nil }
        var seen = 0
        var oldest: String?
        for message in messages.reversed() where message.authorId != currentUserId && !message.content.isService {
            seen += 1
            oldest = message.id
            if seen == unread { return message.id }
        }
        return complete ? oldest : nil
    }
}
