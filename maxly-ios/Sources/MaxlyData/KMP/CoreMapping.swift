import Foundation
import MaxlyDomain

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
    /// Публичный чат из поиска. Без названия — по типу: «Канал», «Группа» или «Чат».
    static func searchResult(_ found: CoreSearchChat) -> ChatSearchResult {
        let type = ChatType.fromCore(found.type)
        let title = found.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback: String
        switch type {
        case .channel: fallback = "Канал"
        case .group: fallback = "Группа"
        case .private: fallback = "Чат"
        }
        let subtitle = found.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatSearchResult(
            id: found.id,
            title: title.isEmpty ? fallback : title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            type: type,
            avatarURL: found.avatarURL.isEmpty ? nil : URL(string: found.avatarURL)
        )
    }

    /// Найденное сообщение; без чата (id 0) и без текста — `nil`.
    static func foundMessage(_ found: CoreFoundMessage) -> FoundMessage? {
        let text = found.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !found.chatId.isEmpty, found.chatId != "0", !text.isEmpty else { return nil }
        return FoundMessage(
            chatId: found.chatId,
            messageId: found.messageId,
            senderId: found.senderId,
            text: text,
            date: found.timeMs > 0 ? Date(timeIntervalSince1970: TimeInterval(found.timeMs) / 1000) : nil
        )
    }

    static func chat(_ chat: CoreChat) -> ChatRecord {
        var record = ChatRecord(
            id: chat.id,
            title: chat.title,
            type: ChatType.fromCore(chat.type),
            lastMessageId: chat.lastMessageId.isEmpty ? nil : chat.lastMessageId,
            unreadCount: chat.unread,
            updatedAt: Date(unixMillis: chat.updatedAtMs),
            preview: chat.lastText.isEmpty ? nil : chat.lastText,
            lastAuthorId: chat.lastAuthorId.isEmpty ? nil : chat.lastAuthorId,
            avatarURL: chat.avatarURL.isEmpty ? nil : URL(string: chat.avatarURL),
            isMuted: chat.muted < 0 ? nil : chat.muted == 1,
            lastMedia: MessageMediaKind(rawValue: chat.lastMedia),
            lastThumbnailURL: chat.lastThumbURL.isEmpty ? nil : URL(string: chat.lastThumbURL),
            commentsEnabled: chat.comments < 0 ? nil : chat.comments == 1,
            canWrite: chat.canWrite < 0 ? nil : chat.canWrite == 1,
            lastAuthorName: chat.lastAuthorName.isEmpty ? nil : chat.lastAuthorName,
            lastOutgoing: chat.lastFromMe < 0 ? nil : chat.lastFromMe == 1,
            lastForwarded: chat.lastForwarded,
            peerReadMark: chat.peerReadMs,
            lastMessageAt: chat.lastTimeMs
        )
        record.isActive = chat.active
        // Ядро пересчитывает флаг, когда узнаёт собеседника, поэтому его ответ — всегда правда.
        // Мини-приложение бывает только у бота: заодно строка узнаёт, что это бот.
        record.hasWebApp = chat.hasWebApp
        if chat.hasWebApp { record.isBot = true }
        if let control = chat.lastControl, let text = serviceText(control, messageText: chat.lastText) {
            record.preview = text
            record.lastMedia = .service
        }
        return record
    }

    /// Текст служебного последнего сообщения для строки списка: текст ядра, иначе текст
    /// сервера, у закрепления — слова ядра (`ServiceText.text(pin)`), иначе текст самого
    /// сообщения, иначе «Служебное сообщение».
    static func serviceText(_ control: CoreControl, messageText: String) -> String? {
        let server = [control.fallbackText, control.shortMessage, control.message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let server { return server }
        if let pin = pinNotice(control) { return ServiceText.text(pin) }
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? ServiceText.fallback : text
    }

    /// Закрепление из вложения ядра; `nil` — не `pin` / `unpin`.
    static func pinNotice(_ control: CoreControl) -> PinNotice? {
        switch control.event.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pin":
            let id = control.pinnedMessageId?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PinNotice(
                messageId: id?.isEmpty == false && id != "0" ? id : nil,
                preview: control.pinnedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                unpinned: false
            )
        case "unpin":
            return PinNotice(messageId: nil, preview: "", unpinned: true)
        default:
            return nil
        }
    }

    static func contact(_ contact: CoreContact, now: Date = Date()) -> Contact {
        let presence = Self.presence(status: contact.presence, online: contact.online, seenMs: contact.lastSeenMs)
        return Contact(
            id: contact.id,
            firstName: contact.firstName,
            lastName: contact.lastName,
            phone: contact.phone.isEmpty ? nil : "+" + contact.phone,
            avatarURL: contact.avatarURL.isEmpty ? nil : URL(string: contact.avatarURL),
            presence: presence,
            isBot: contact.isBot,
            isOfficial: contact.isOfficial,
            isServiceAccount: contact.isServiceAccount
        )
    }

    /// Код статуса ядра (`presence`, `-1` — не прислан); без кода — «в сети» и время, как раньше.
    static func presence(status: Int, online: Bool, seenMs: Int64) -> Contact.Presence {
        if status >= 0 { return Contact.Presence.server(status: status, seenMs: seenMs) }
        return Contact.Presence.server(status: online ? 1 : Contact.Presence.noStatus, seenMs: seenMs)
    }

    static func profile(_ core: CoreProfile) -> ChatProfile {
        let presence = Self.presence(status: core.presence, online: core.online, seenMs: core.lastSeenMs)
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
            commands: core.commands.map { ChatProfile.BotCommand(name: $0.name, description: text($0.description)) },
            hasWebApp: core.hasWebApp,
            commentsEnabled: core.commentsEnabled
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
        if let control = message.control { content = withControl(control, content) }
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
            reactionsKnown: reactions != nil,
            updateTimeMs: max(message.updateTimeMs, 0)
        )
    }

    /// Служебное вложение ядра поверх разобранного фрагмента: текст ядра (`coreText`, его
    /// показывают лента, строка списка и уведомление), а без `CONTROL` во фрагменте — само
    /// событие. Закрепление — своя плашка (`PinNotice`) с текстом ядра и id закреплённого.
    static func withControl(_ control: CoreControl, _ content: MessageContent) -> MessageContent {
        let event = control.event.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = control.fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines)
        var copy = content
        if content.pin != nil || ["pin", "unpin"].contains(event.lowercased()) {
            guard var pin = content.pin ?? pinNotice(control) else { return content }
            if pin.messageId?.isEmpty != false, !pin.isUnpin, let id = pinNotice(control)?.messageId { pin.messageId = id }
            if pin.preview.isEmpty, let text = pinNotice(control)?.preview, !text.isEmpty { pin.preview = text }
            if let fallback, !fallback.isEmpty { pin.coreText = fallback }
            copy.pin = pin
            return copy
        }
        var notice = content.service ?? ServiceNotice(
            event: event,
            userIds: control.userIds.filter { !$0.isEmpty && $0 != "0" },
            title: control.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? control.title : nil
        )
        if let fallback, !fallback.isEmpty { notice.coreText = fallback }
        if notice.text == nil {
            notice.text = [control.shortMessage, control.message]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
        copy.service = notice
        return copy
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
            return .server(code: failure.key ?? failure.kind, text: failure.serverText)
        case "NOT_FOUND":
            return .invalidResponse
        case "MALFORMED_REPLY":
            // Сервер ответил без нужных полей: это его сбой, а не ошибка пользователя.
            return .server(code: failure.kind, text: nil)
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
        if let control = event.control { content = CoreMapping.withControl(control, content) }
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
            reactionsKnown: reactions != nil,
            updateTimeMs: max(event.updateTimeMs, 0)
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
