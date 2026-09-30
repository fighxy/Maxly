import Foundation
import OrbitleDomain

extension Date {
    /// Время сообщения и `from` истории в ядре — миллисекунды Unix.
    public init(unixMillis: Int64) {
        self.init(timeIntervalSince1970: Double(unixMillis) / 1000)
    }

    public var unixMillis: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}

enum CoreMapping {
    static func chat(_ chat: CoreChat) -> ChatRecord {
        ChatRecord(
            id: chat.id,
            title: chat.title,
            type: ChatType.fromCore(chat.type),
            lastMessageId: chat.lastMessageId.isEmpty ? nil : chat.lastMessageId,
            unreadCount: chat.unread,
            updatedAt: Date(unixMillis: chat.updatedAtMs),
            preview: chat.lastText.isEmpty ? nil : chat.lastText,
            lastAuthorId: chat.lastAuthorId.isEmpty ? nil : chat.lastAuthorId,
            avatarURL: chat.avatarURL.isEmpty ? nil : URL(string: chat.avatarURL),
            lastMedia: MessageMediaKind(rawValue: chat.lastMedia),
            lastThumbnailURL: chat.lastThumbURL.isEmpty ? nil : URL(string: chat.lastThumbURL),
            commentsEnabled: chat.comments < 0 ? nil : chat.comments == 1,
            canWrite: chat.canWrite < 0 ? nil : chat.canWrite == 1
        )
    }

    static func contact(_ contact: CoreContact, now: Date = Date()) -> Contact {
        let presence: Contact.Presence
        if contact.online {
            presence = .online
        } else if contact.lastSeenMs > 0 {
            presence = .lastSeen(Date(unixMillis: contact.lastSeenMs))
        } else {
            presence = .unknown
        }
        return Contact(
            id: contact.id,
            firstName: contact.firstName,
            lastName: contact.lastName,
            phone: contact.phone.isEmpty ? nil : "+" + contact.phone,
            avatarURL: contact.avatarURL.isEmpty ? nil : URL(string: contact.avatarURL),
            presence: presence
        )
    }

    static func profile(_ core: CoreProfile) -> ChatProfile {
        let presence: Contact.Presence
        if core.online {
            presence = .online
        } else if core.lastSeenMs > 0 {
            presence = .lastSeen(Date(unixMillis: core.lastSeenMs))
        } else {
            presence = .unknown
        }
        func text(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return ChatProfile(
            kind: ChatProfile.Kind(rawValue: core.kind) ?? .user,
            chatId: core.chatId,
            peerId: text(core.peerId),
            title: core.title,
            avatarURL: text(core.avatarURL).flatMap(URL.init(string:)),
            description: text(core.description),
            link: text(core.link),
            phone: text(core.phone).map { "+" + $0 },
            participants: core.participants > 0 ? core.participants : nil,
            presence: presence,
            isOfficial: core.official,
            isPublic: core.isPublic,
            commands: core.commands.map { ChatProfile.BotCommand(name: $0.name, description: text($0.description)) }
        )
    }

    /// Звонок для экрана. Исход по `hangupType`, как у официального клиента: входящий без
    /// ответа — пропущенный, исходящий без ответа — отменённый, `REJECTED` у исходящего —
    /// собеседник отклонил.
    static func call(_ call: CoreCall) -> CallRecord {
        let outcome: CallRecord.Outcome
        if call.outgoing {
            switch call.hangupType {
            case "REJECTED": outcome = .declined
            case "CANCELED": outcome = .cancelled
            default: outcome = call.duration > 0 ? .answered : .cancelled
            }
        } else {
            outcome = call.missed ? .missed : .answered
        }
        let title = call.title.isEmpty ? (call.isGroup ? "Групповой звонок" : "Звонок") : call.title
        return CallRecord(
            id: call.id,
            peerId: call.peerId.isEmpty ? call.chatId : call.peerId,
            title: title,
            avatarURL: call.avatarURL.isEmpty ? nil : URL(string: call.avatarURL),
            isGroup: call.isGroup,
            chatId: call.chatId.isEmpty ? nil : call.chatId,
            direction: call.outgoing ? .outgoing : .incoming,
            outcome: outcome,
            isVideo: call.video,
            date: Date(unixMillis: call.timeMs),
            duration: nil
        )
    }

    static func message(_ message: CoreMessage) -> MessageRecord {
        var content = MessageContentCodec.decode(message.contentJSON)
        let reactions = MessageContentCodec.reactionUpdate(message.reactionsJSON)
        if let reactions { content.reactions = reactions.applied(to: content.reactions) }
        return MessageRecord(
            id: message.id,
            serverId: message.id,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: Date(unixMillis: message.timeMs),
            status: .sent,
            contentJSON: MessageContentCodec.encode(content),
            threadOf: content.threadOf ?? "",
            authorName: message.authorName,
            authorAvatarURL: message.authorAvatarURL,
            reactionsKnown: reactions != nil
        )
    }

    /// Категория ошибки для репозиториев. `kind` — имя `ErrorKind` ядра.
    static func apiError(_ error: Error) -> MaxAPIError {
        if let error = error as? MaxAPIError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            return error.code == .cancelled ? .cancelled : .offline
        }
        guard let failure = error as? CoreFailure else { return .unknown }
        switch failure.kind {
        case "NETWORK", "TIMEOUT", "CLOSED":
            return .offline
        case "SESSION_EXPIRED":
            return .sessionExpired
        case "AUTH":
            // Отказ шага входа. Вход переводит его сам (`AuthErrors`) с текстом для шага,
            // а вне входа это просто отклонённый запрос, а не «неверный пароль».
            return .invalidResponse
        case "SERVER", "UPLOAD":
            return .server(code: failure.key ?? failure.kind)
        case "NOT_FOUND":
            return .invalidResponse
        case "MALFORMED_REPLY":
            // Сервер ответил без нужных полей: это его сбой, а не ошибка пользователя.
            return .server(code: failure.kind)
        case "CANCELLED":
            return .cancelled
        default:
            return .unknown
        }
    }
}

extension MessageRecord {
    init?(_ event: CoreEvent) {
        guard event.kind == .message || event.kind == .edited, !event.messageId.isEmpty, !event.chatId.isEmpty else { return nil }
        var content = MessageContentCodec.decode(event.contentJSON)
        let reactions = MessageContentCodec.reactionUpdate(event.reactionsJSON)
        if let reactions { content.reactions = reactions.applied(to: content.reactions) }
        self.init(
            id: event.messageId,
            serverId: event.messageId,
            chatId: event.chatId,
            authorId: event.authorId,
            text: event.text,
            timestamp: Date(unixMillis: event.timeMs),
            status: .sent,
            contentJSON: MessageContentCodec.encode(content),
            threadOf: content.threadOf ?? "",
            authorName: event.authorName,
            authorAvatarURL: event.authorAvatarURL,
            reactionsKnown: reactions != nil
        )
    }
}

extension ChatRecord {
    init?(_ event: CoreEvent) {
        guard event.kind == .chat, !event.chatId.isEmpty else { return nil }
        self.init(
            id: event.chatId,
            title: event.title,
            type: ChatType.fromCore(event.chatType),
            lastMessageId: event.messageId.isEmpty ? nil : event.messageId,
            unreadCount: max(event.unread, 0),
            updatedAt: Date(unixMillis: event.timeMs),
            preview: event.text.isEmpty ? nil : event.text
        )
    }
}
