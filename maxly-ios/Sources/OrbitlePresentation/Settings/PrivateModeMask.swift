import Foundation
import OrbitleDomain

/// Во что приватный режим превращает строки и сообщения. Только замена того, что видно:
/// id, время, статусы и счётчики остаются, чтобы списки и лента работали как обычно.
public enum PrivateModeMask {
    public static let sentText = "Вы отправили сообщение"
    public static let receivedText = "Вы получили сообщение"
    /// Текст черновика в строке чата: «Черновик: скрыт».
    public static let draftText = "скрыт"
    public static let contactTitle = "Контакт"
    public static let participantTitle = "Участник"
    public static let searchResultTitle = "Чат"
    public static let archiveTitle = "Скрытый чат"
    public static let archivePreview = "Сообщение скрыто"
    /// Подсказка под плашкой в чате.
    public static let revealHint = "Нажмите на сообщение, чтобы просмотреть исходное содержимое"
    public static let revealAccessibilityHint = "Покажет сообщение на 15 секунд"

    public static func messageText(outgoing: Bool) -> String {
        outgoing ? sentText : receivedText
    }

    /// Подпись-заглушка конкретного сообщения. Звонок остаётся звонком, но без направления,
    /// исхода и длительности — как строка вкладки «Звонки» в приватном режиме.
    public static func messageText(for message: Message, outgoing: Bool) -> String {
        if let call = message.content.call { return callTitle(isGroup: call.isGroup) }
        return messageText(outgoing: outgoing)
    }

    /// Общий заголовок чата по типу. «Избранное» своё и ничего не выдаёт, оно остаётся.
    public static func chatTitle(type: ChatType, isSavedMessages: Bool = false) -> String {
        if isSavedMessages { return ChatListFormatter.savedMessagesTitle }
        switch type {
        case .private: return "Личный чат"
        case .group: return "Групповой чат"
        case .channel: return "Канал"
        }
    }

    public static func chatTitle(for item: ChatListItem) -> String {
        chatTitle(type: item.type, isSavedMessages: item.avatar.kind == .savedMessages)
    }

    public static func callTitle(isGroup: Bool) -> String {
        CallBubbleText.preview(isGroup: isGroup)
    }

    /// Однотонный круг того же цвета: без фото и букв. Значки «Избранного» и архива остаются.
    public static func avatar(_ avatar: ChatAvatar) -> ChatAvatar {
        switch avatar.kind {
        case .savedMessages, .archive:
            return avatar
        case .initials, .photo:
            return ChatAvatar(kind: .initials(""), colorIndex: avatar.colorIndex)
        }
    }

    /// Строка списка чатов без имени, аватара, автора, текста и миниатюры.
    public static func item(_ item: ChatListItem) -> ChatListItem {
        let title = chatTitle(for: item)
        let preview: String
        switch item.previewStyle {
        case .message:
            switch item.media {
            case .call: preview = callTitle(isGroup: false)
            case .groupCall: preview = callTitle(isGroup: true)
            default: preview = messageText(outgoing: item.lastIsOutgoing)
            }
        case .draft: preview = draftText
        // «печатает…» — без имён печатающих; «Нет сообщений» имён не содержит.
        case .typing: preview = item.anonymousTyping ?? item.preview
        case .empty: preview = item.preview
        }
        var masked = ChatListItem(
            id: item.id,
            title: title,
            type: item.type,
            avatar: avatar(item.avatar),
            isOnline: false,
            isMuted: item.isMuted,
            isVerified: false,
            isBot: false,
            isPinned: item.isPinned,
            sender: nil,
            preview: preview,
            previewStyle: item.previewStyle,
            media: nil,
            thumbnailURL: nil,
            delivery: item.delivery,
            time: item.time,
            unreadCount: item.unreadCount,
            unreadBadge: item.unreadBadge,
            badge: item.badge,
            badgeMuted: item.badgeMuted,
            hasMention: item.hasMention,
            accessibilityLabel: "",
            isForwarded: false,
            lastIsOutgoing: item.lastIsOutgoing
        )
        masked = masked.withAccessibility(spoken(masked))
        return masked
    }

    public static func archive(_ summary: ChatArchiveSummary) -> ChatArchiveSummary {
        ChatArchiveSummary(
            count: summary.count,
            unreadCount: summary.unreadCount,
            title: archiveTitle,
            preview: archivePreview
        )
    }

    /// Сообщение ленты: только общая подпись, время и статус. Автор остаётся id — по нему
    /// склеиваются пузыри подряд и выбирается цвет круга, — но без имени и фото.
    public static func message(_ message: Message, outgoing: Bool) -> Message {
        Message(
            id: message.id,
            serverId: message.serverId,
            chatId: message.chatId,
            authorId: message.authorId,
            text: messageText(for: message, outgoing: outgoing),
            timestamp: message.timestamp,
            status: message.status,
            content: .empty
        )
    }

    private static func spoken(_ item: ChatListItem) -> String {
        var parts = [item.title]
        if item.isPinned { parts.append("закреплён") }
        if item.isMuted { parts.append("без звука") }
        switch item.previewStyle {
        case .draft: parts.append("черновик скрыт")
        case .message, .typing, .empty: parts.append(item.preview)
        }
        if !item.time.isEmpty { parts.append(item.time) }
        if item.unreadCount > 0 {
            parts.append(ChatListFormatter.unreadPhrase(item.unreadCount))
        } else if item.badge == .dot {
            parts.append("помечен непрочитанным")
        }
        if item.hasMention { parts.append("есть упоминание") }
        return parts.joined(separator: ", ")
    }
}
