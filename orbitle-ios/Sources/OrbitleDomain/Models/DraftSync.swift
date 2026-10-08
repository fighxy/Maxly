import Foundation

/// Черновик поля ввода в виде, общем для устройства и сервера. `updateTime` — мс: у
/// сохранённого на сервере — время ответа `DRAFT_SAVE`, у локального — время правки.
public struct SyncedDraft: Hashable, Sendable {
    public var text: String
    public var spans: [TextSpan]
    public var replyTo: String?
    public var updateTime: Int64

    public init(text: String, spans: [TextSpan] = [], replyTo: String? = nil, updateTime: Int64) {
        self.text = text
        self.spans = spans
        self.replyTo = replyTo
        self.updateTime = updateTime
    }

    /// Пустой текст без ответа — черновика нет (такой черновик стирается).
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (replyTo?.isEmpty ?? true)
    }
}

/// Правила черновиков сервера (`DRAFT_SAVE` 176, `DRAFT_DISCARD` 177). Общие с Kotlin
/// сценарии — `test-fixtures/drafts`. Только смысл, без задержек и таймеров.
public enum DraftSync {
    /// Куда адресован черновик: в личном чате, с ботом и в «Избранном» — `userId`
    /// собеседника (в «Избранном» — свой id), в группе и канале — `chatId`.
    public enum Address: Hashable, Sendable {
        case user(String)
        case chat(String)

        public var key: String {
            switch self {
            case .user: "userId"
            case .chat: "chatId"
            }
        }

        public var id: String {
            switch self {
            case .user(let id), .chat(let id): id
            }
        }
    }

    public static func address(chatId: String, type: ChatType, peerId: String?, me: String) -> Address? {
        if chatId == Chat.savedMessagesId { return .user(me) }
        switch type {
        case .private:
            guard let peerId, !peerId.isEmpty else { return nil }
            return .user(peerId)
        case .group, .channel:
            return .chat(chatId)
        }
    }

    /// Итог слияния черновика устройства и сервера.
    ///
    /// - Пустой черновик (пустой текст без ответа) считается отсутствующим.
    /// - Из двух непустых побеждает более новый `updateTime`; при равном остаётся локальный.
    /// - Стирание с сервера (`discarded`, мс) не раньше победителя стирает черновик.
    public static func merge(local: SyncedDraft?, server: SyncedDraft?, discardedAt: Int64?) -> SyncedDraft? {
        let mine = local.flatMap { $0.isEmpty ? nil : $0 }
        let theirs = server.flatMap { $0.isEmpty ? nil : $0 }
        let winner: SyncedDraft?
        switch (mine, theirs) {
        case let (l?, s?): winner = s.updateTime > l.updateTime ? s : l
        case let (l?, nil): winner = l
        case let (nil, s?): winner = s
        case (nil, nil): winner = nil
        }
        guard let winner else { return nil }
        if let discardedAt, discardedAt >= winner.updateTime { return nil }
        return winner
    }

    /// Запрос, который надо послать, когда пользователь ушёл из поля с черновиком [local].
    public enum Request: Hashable, Sendable {
        /// `DRAFT_SAVE` 176 `{chatId | userId, draft: {text, elements, replyTo?}}`.
        case save(Address, text: String, elements: [MessageMarkup.Element], replyTo: String?)
        /// `DRAFT_DISCARD` 177 `{chatId | userId, time}`: `time` — `updateTime` черновика сервера.
        case discard(Address, time: Int64)
    }

    /// Что отправить: непустой черновик, не совпадающий с сохранённым на сервере, — сохранить;
    /// пустой при черновике на сервере — стереть его; иначе ничего.
    public static func request(local: SyncedDraft?, server: SyncedDraft?, address: Address) -> Request? {
        let mine = local.flatMap { $0.isEmpty ? nil : $0 }
        let theirs = server.flatMap { $0.isEmpty ? nil : $0 }
        if let mine {
            let trimmed = MessageMarkup.trimmed(mine.text, spans: mine.spans)
            if let theirs {
                let same = MessageMarkup.trimmed(theirs.text, spans: theirs.spans)
                if same.text == trimmed.text, theirs.replyTo == mine.replyTo,
                   MessageMarkup.elements(same.spans, text: same.text) == MessageMarkup.elements(trimmed.spans, text: trimmed.text) {
                    return nil
                }
            }
            return .save(address, text: trimmed.text, elements: MessageMarkup.elements(trimmed.spans, text: trimmed.text), replyTo: mine.replyTo)
        }
        if let theirs { return .discard(address, time: theirs.updateTime) }
        return nil
    }
}
