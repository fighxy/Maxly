import Foundation
import OrbitlDomain

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
            preview: chat.lastText.isEmpty ? nil : chat.lastText
        )
    }

    static func message(_ message: CoreMessage) -> MessageRecord {
        MessageRecord(
            id: message.id,
            serverId: message.id,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: Date(unixMillis: message.timeMs),
            status: .sent
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
        self.init(
            id: event.messageId,
            serverId: event.messageId,
            chatId: event.chatId,
            authorId: event.authorId,
            text: event.text,
            timestamp: Date(unixMillis: event.timeMs),
            status: .sent
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

enum CoreErrors {
    static func orbitl(_ error: Error) -> OrbitlError {
        if let error = error as? OrbitlError { return error }
        return CoreMapping.apiError(error).orbitlError
    }
}
