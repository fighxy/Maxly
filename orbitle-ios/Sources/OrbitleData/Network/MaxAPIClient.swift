import Foundation
import OrbitleDomain

/// Ошибки серверных вызовов.
public enum MaxAPIError: Error, Sendable, Equatable {
    /// Нет сети или соединение с сервером потеряно.
    case offline
    /// Сервер вернул ошибку с кодом.
    case server(code: String)
    /// Сохранённый токен больше не действует.
    case sessionExpired
    /// Ввод отклонён, например неверный пароль.
    case rejected(String)
    /// Запрос неверен или объект не найден.
    case invalidResponse
    /// Вызов отменён (задача отменена, ядро закрыто или ответ пришёл на устаревший запрос).
    case cancelled
    /// Ошибка без категории (сбой ядра, неверный аргумент).
    case unknown

    /// Имеет ли смысл повторить запрос позже.
    public var isRetryable: Bool {
        switch self {
        case .offline, .server: true
        case .invalidResponse, .sessionExpired, .rejected, .cancelled, .unknown: false
        }
    }

    /// Категория ошибки для UI (architecture.md, «Ошибки и офлайн»).
    public var orbitleError: OrbitleError {
        switch self {
        case .offline: .networkUnavailable
        case .server(let code): .server(code: code)
        case .sessionExpired: .authExpired
        case .rejected(let message): .rejected(message)
        case .invalidResponse: .invalidRequest
        case .cancelled: .cancelled
        case .unknown: .unknown
        }
    }
}

/// Ответ сервера на отправку сообщения.
public struct SentMessage: Sendable, Hashable {
    public var serverId: String
    public var timestamp: Date

    public init(serverId: String, timestamp: Date) {
        self.serverId = serverId
        self.timestamp = timestamp
    }
}

/// Серверные вызовы, которые нужны репозиториям. Протокол, чтобы в тестах
/// подставлять фейковую реализацию.
public protocol MaxAPI: Sendable {
    func fetchChats() async -> Result<[ChatRecord], MaxAPIError>
    /// Один чат. Ошибка, если сервер его не вернул.
    func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError>
    /// Сообщения чата строго старше `before` (самые новые, если `nil`), не больше `limit`.
    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// `clientId` это локальный id. Ядро само ставит числовой `cid` в пакет, локальный id на сервер не уходит.
    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError>
    /// Ответ на сообщение `replyTo` (серверный id). `nil` — обычное сообщение.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError>
    /// Заменить текст отправленного сообщения (по серверному id).
    func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError>
    /// Удалить сообщения по серверным id: у себя или у всех.
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError>
    /// Переслать сообщение. Ответ — новое сообщение в целевом чате.
    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError>
    /// `messageId` nil значит, что локально нечего отмечать: сервер не вызывается.
    func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError>
    /// Закреплённые чаты целиком, сверху вниз. Ответ — список, который подтвердил сервер.
    func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError>
    /// Выключить уведомления чата насовсем или включить обратно.
    func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError>
    /// Серверные папки для полосы над списком, без «Все»: сразу, если известны, и после
    /// каждого изменения. Пустой массив — папок нет.
    func folderUpdates() -> AsyncStream<[ChatFolder]>
    /// Поставить свою реакцию `emoji` на сообщение (серверный id) или снять её (`nil`).
    /// Непустой `postId` — комментарий этого поста. Ответ — реакции, если сервер их прислал.
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError>
    /// Реакции сообщений по серверным id. Сообщения, о которых сервер промолчал, пропущены.
    func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError>
    /// Кто поставил реакции на сообщение.
    func reactionUsers(chatId: String, messageId: String) async -> Result<[ReactionUser], MaxAPIError>
    /// Расшифровка голосового: `messageId` серверный, `audioId` — id вложения.
    func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError>
    /// Эмодзи каталога реакций сервера.
    func reactionCatalog() async -> Result<[String], MaxAPIError>
    /// Загрузить вложения и отправить одним сообщением с подписью. Контакт уходит один,
    /// без подписи. `replyTo` — серверный id цитаты. Отмена задачи отменяет загрузку.
    func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                         progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError>
}

public extension MaxAPI {
    /// Источник без серверных закреплённых: запрос отклоняется.
    func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError> { .failure(.invalidResponse) }
    func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    /// Источник без серверных папок.
    func folderUpdates() -> AsyncStream<[ChatFolder]> { AsyncStream { $0.yield([]); $0.finish() } }
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без реакций: изменения откатываются, каталог пуст.
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError> {
        .failure(.invalidResponse)
    }
    func reactionUsers(chatId: String, messageId: String) async -> Result<[ReactionUser], MaxAPIError> {
        .failure(.invalidResponse)
    }
    func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func reactionCatalog() async -> Result<[String], MaxAPIError> { .failure(.invalidResponse) }
    /// Источник без загрузок.
    func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                         progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без ответов отправляет просто текст.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId)
    }
}

/// Клиент API Max поверх `MaxCore`. Типы Kotlin сюда не попадают.
public final class MaxAPIClient: MaxAPI, Sendable {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func fetchChats() async -> Result<[ChatRecord], MaxAPIError> {
        await catching {
            // Строки списка полные: пустое последнее сообщение значит «сообщений нет».
            try await core.loadChats().map { chat in
                var record = CoreMapping.chat(chat)
                record.lastKnown = true
                return record
            }
        }
    }

    public func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError> {
        await catching {
            try CoreMapping.chat(await core.loadChat(id: id))
        }
    }

    public func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadHistory(chatId: chatId, beforeMs: before?.unixMillis ?? 0, limit: limit)
            return page.map(CoreMapping.message)
        }
    }

    public func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: nil)
    }

    public func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError> {
        _ = clientId
        return await catching {
            let sent: CoreMessage
            if let replyTo, !replyTo.isEmpty {
                sent = try await core.sendText(chatId: chatId, text: text, replyTo: replyTo)
            } else {
                sent = try await core.sendText(chatId: chatId, text: text)
            }
            return SentMessage(serverId: sent.id, timestamp: Date(unixMillis: sent.timeMs))
        }
    }

    public func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError> {
        await catching {
            CoreMapping.message(try await core.editMessage(chatId: chatId, messageId: messageId, text: text))
        }
    }

    public func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone)
        }
    }

    public func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError> {
        await catching {
            CoreMapping.message(try await core.forwardMessage(toChatId: toChatId, fromChatId: fromChatId, messageId: messageId))
        }
    }

    public func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.setChatMuted(chatId: chatId, muted: muted)
        }
    }

    public func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError> {
        guard let messageId, !messageId.isEmpty else { return .success(()) }
        return await catching {
            try await core.markRead(chatId: chatId, messageId: messageId)
        }
    }

    public func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError> {
        await catching {
            let json = try await core.setReaction(chatId: chatId, messageId: messageId, postId: postId, emoji: emoji ?? "")
            return MessageContentCodec.reactionUpdate(json)
        }
    }

    public func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError> {
        await catching {
            try await core.loadReactions(chatId: chatId, messageIds: messageIds)
                .compactMapValues(MessageContentCodec.reactionUpdate)
        }
    }

    public func reactionUsers(chatId: String, messageId: String) async -> Result<[ReactionUser], MaxAPIError> {
        await catching {
            try await core.loadReactionUsers(chatId: chatId, messageId: messageId)
        }
    }

    public func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError> {
        await catching {
            try await core.transcribeVoice(chatId: chatId, messageId: messageId, audioId: audioId)
        }
    }

    public func reactionCatalog() async -> Result<[String], MaxAPIError> {
        await catching {
            try await core.loadReactionCatalog()
        }
    }

    public func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                                progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError> {
        let reply = replyTo.flatMap { Int64($0) == nil ? nil : $0 } ?? ""
        if let contact = drafts.first(where: { $0.kind == .contact }) {
            // Карточка контакта — отдельное сообщение: у него нет файла и подписи.
            guard drafts.count == 1, !contact.contactId.isEmpty else { return .failure(.invalidResponse) }
            return await catching {
                CoreMapping.message(try await core.sendContact(chatId: chatId, contactId: contact.contactId, replyTo: reply))
            }
        }
        if let recording = drafts.first(where: \.isRecording) {
            // Голосовое и кружок — отдельное сообщение со своим слотом загрузки.
            guard drafts.count == 1, !recording.path.isEmpty else { return .failure(.invalidResponse) }
            return await catching {
                CoreMapping.message(try await core.sendRecording(
                    chatId: chatId, path: recording.path, kind: recording.kind.rawValue,
                    durationMs: recording.durationMs, wave: recording.waveform, replyTo: reply, progress: progress
                ))
            }
        }
        let items = drafts.map { draft in
            CoreOutgoingMedia(path: draft.path, kind: draft.kind.rawValue, fileName: draft.fileName)
        }
        guard !items.isEmpty, !items.contains(where: { $0.path.isEmpty }) else { return .failure(.invalidResponse) }
        return await catching {
            CoreMapping.message(try await core.sendMedia(chatId: chatId, items: items, caption: caption, replyTo: reply, progress: progress))
        }
    }

    public func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError> {
        await catching {
            try await core.setPinnedChats(chatIds)
        }
    }

    public func folderUpdates() -> AsyncStream<[ChatFolder]> {
        let source = core.folders()
        return AsyncStream { continuation in
            let task = Task {
                for await folders in source {
                    continuation.yield(folders.filter { !$0.isAllChats }.map(\.chatFolder))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func catching<T>(_ body: () async throws -> T) async -> Result<T, MaxAPIError> {
        do {
            return .success(try await body())
        } catch {
            return .failure(CoreMapping.apiError(error))
        }
    }
}
