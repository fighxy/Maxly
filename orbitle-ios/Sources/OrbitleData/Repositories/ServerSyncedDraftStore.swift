import Foundation
import OrbitleDomain

/// Черновики устройства, сверенные с черновиками сервера (`DRAFT_SAVE` 176, `DRAFT_DISCARD` 177).
///
/// При открытии чата побеждает более новый из двух (`DraftSync.merge`, test-fixtures/drafts);
/// черновик сервера записывается на устройство. Пока печатают, черновик живёт только на
/// устройстве; серверу он уходит, когда из чата ушли (`commitDraft`): непустой — сохраняется,
/// пустой при черновике на сервере — стирается там. Черновик из одного ответа (без текста) —
/// тоже черновик. Вложения в черновик не попадают никогда. После отправки черновик стирает
/// ядро. Черновики с других устройств приходят событиями `draft` (`serverDraftChanged`).
///
/// Текст хранит база устройства, ответ — `replies` (серверный id сообщения и время). Разметку
/// черновика база пока не хранит: на сервер уходят текст и ответ.
public actor ServerSyncedDraftStore: ChatDraftStore {
    /// Ответ черновика на устройстве.
    public struct ReplyMark: Codable, Hashable, Sendable {
        public var messageId: String
        /// Когда ответ выбрали, мс.
        public var time: Int64

        public init(messageId: String, time: Int64) {
            self.messageId = messageId
            self.time = time
        }
    }

    /// Где лежат ответы черновиков: по умолчанию `UserDefaults`.
    public struct ReplyStorage: Sendable {
        public var load: @Sendable () -> [String: ReplyMark]
        public var store: @Sendable ([String: ReplyMark]) -> Void

        public init(load: @escaping @Sendable () -> [String: ReplyMark], store: @escaping @Sendable ([String: ReplyMark]) -> Void) {
            self.load = load
            self.store = store
        }

        public static let userDefaults = ReplyStorage(
            load: {
                guard let data = UserDefaults.standard.data(forKey: "draftReplies") else { return [:] }
                return (try? JSONDecoder().decode([String: ReplyMark].self, from: data)) ?? [:]
            },
            store: { replies in
                UserDefaults.standard.set(try? JSONEncoder().encode(replies), forKey: "draftReplies")
            }
        )

        public static func memory() -> ReplyStorage {
            let box = ReplyBox()
            return ReplyStorage(load: { box.value }, store: { box.value = $0 })
        }
    }

    private let local: any ChatDraftStore
    private let core: any MaxCore
    private let storage: ReplyStorage
    private let now: @Sendable () -> Date
    private var replies: [String: ReplyMark]
    /// Время черновика сервера, который стёрли (отсюда или на сервере): ядро может ещё помнить его.
    private var discarded: [String: Int64] = [:]
    /// Время последнего черновика сервера по чату: стирание на сервере сравнивается с ним.
    private var lastServerTime: [String: Int64] = [:]
    private var listeners: [UUID: AsyncStream<String>.Continuation] = [:]

    public init(
        local: any ChatDraftStore,
        core: any MaxCore,
        replies storage: ReplyStorage = .userDefaults,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.local = local
        self.core = core
        self.storage = storage
        self.now = now
        self.replies = storage.load()
    }

    public func draft(chatId: String) async -> String? {
        let mine = await local.draft(chatId: chatId)
        guard Self.syncs(chatId) else { return mine }
        let device = await deviceDraft(chatId)
        let server = await serverDraft(chatId)
        guard let winner = DraftSync.merge(local: device, server: server, discardedAt: discarded[chatId]) else {
            return mine
        }
        let text = winner.text.isEmpty ? nil : winner.text
        if text != mine {
            await local.saveDraft(winner.text, chatId: chatId)
        }
        if winner.replyTo != replies[chatId]?.messageId {
            setReply(winner.replyTo.map { ReplyMark(messageId: $0, time: winner.updateTime) }, chatId: chatId)
        }
        return text
    }

    public func saveDraft(_ text: String, chatId: String) async {
        await local.saveDraft(text, chatId: chatId)
    }

    public func draftTime(chatId: String) async -> Date? {
        await local.draftTime(chatId: chatId)
    }

    public func draftReply(chatId: String) async -> String? {
        replies[chatId]?.messageId
    }

    public func saveDraftReply(_ messageId: String?, chatId: String) async {
        setReply(messageId.map { ReplyMark(messageId: $0, time: Self.millis(now())) }, chatId: chatId)
    }

    public func commitDraft(chatId: String) async {
        guard Self.syncs(chatId) else { return }
        let device = await deviceDraft(chatId) ?? SyncedDraft(text: "", updateTime: 0)
        let server = await serverDraft(chatId)
        switch DraftSync.request(local: device, server: server, address: .chat(chatId)) {
        case let .save(_, text, elements, replyTo):
            do {
                let saved = try await core.saveDraft(
                    chatId: chatId, text: text, elementsJSON: MessageMarkup.json(elements), replyTo: replyTo ?? ""
                )
                if saved > 0 { lastServerTime[chatId] = saved }
            } catch {
                Log.warning(.messages, "Черновик не сохранён на сервере: \(error)")
            }
        case let .discard(_, serverTime):
            await discard(chatId: chatId, time: serverTime)
        case nil:
            break
        }
    }

    /// Черновик сервера изменился не отсюда (событие `draft` ядра). Новый черновик сервера,
    /// который новее черновика устройства, записывается на устройство; стёртый на сервере
    /// стирает и черновик устройства, если тот не новее. Экран чата узнаёт об этом из
    /// `draftChanges`.
    public func serverDraftChanged(chatId: String, draft: CoreDraft?) async {
        guard Self.syncs(chatId) else { return }
        let device = await deviceDraft(chatId)
        if let draft {
            let server = Self.synced(draft)
            lastServerTime[chatId] = server.updateTime
            guard let winner = DraftSync.merge(local: device, server: server, discardedAt: discarded[chatId]),
                  winner != device else { return }
            await apply(winner, chatId: chatId)
        } else {
            let gone = lastServerTime[chatId] ?? 0
            discarded[chatId] = max(discarded[chatId] ?? 0, gone)
            guard let device, DraftSync.merge(local: device, server: nil, discardedAt: gone) == nil else { return }
            await apply(nil, chatId: chatId)
        }
        for listener in listeners.values { listener.yield(chatId) }
    }

    public func draftChanges() async -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    /// Черновик на устройство: текст в базу, ответ — в `replies`. `nil` стирает оба.
    private func apply(_ draft: SyncedDraft?, chatId: String) async {
        await local.saveDraft(draft?.text ?? "", chatId: chatId)
        let reply = draft?.replyTo.flatMap { $0.isEmpty ? nil : $0 }
        if reply != replies[chatId]?.messageId {
            setReply(reply.map { ReplyMark(messageId: $0, time: draft?.updateTime ?? 0) }, chatId: chatId)
        }
    }

    private func discard(chatId: String, time: Int64) async {
        do {
            try await core.discardDraft(chatId: chatId, time: time)
            discarded[chatId] = max(discarded[chatId] ?? 0, time)
        } catch {
            Log.warning(.messages, "Черновик не стёрт на сервере: \(error)")
        }
    }

    /// Черновик устройства: текст из базы и ответ; время — позднее из двух.
    private func deviceDraft(_ chatId: String) async -> SyncedDraft? {
        let text = await local.draft(chatId: chatId) ?? ""
        let reply = replies[chatId]
        guard !text.isEmpty || reply != nil else { return nil }
        let textTime = await local.draftTime(chatId: chatId).map(Self.millis) ?? 0
        return SyncedDraft(text: text, replyTo: reply?.messageId, updateTime: max(textTime, reply?.time ?? 0))
    }

    /// Черновик сервера, который держит ядро (вход, пуши 152/153, свои сохранения). Стёртый
    /// не возвращается, даже если ядро ещё помнит его.
    private func serverDraft(_ chatId: String) async -> SyncedDraft? {
        let cut = discarded[chatId] ?? Int64.min
        guard let draft = await core.serverDrafts().first(where: { $0.chatId == chatId }).map(Self.synced),
              draft.updateTime > cut else { return nil }
        lastServerTime[chatId] = draft.updateTime
        return draft
    }

    private func setReply(_ mark: ReplyMark?, chatId: String) {
        replies[chatId] = mark
        storage.store(replies)
    }

    static func synced(_ draft: CoreDraft) -> SyncedDraft {
        let elements = draft.elementsJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        return SyncedDraft(
            text: draft.text,
            spans: MessageMarkup.parse(elements, text: draft.text),
            replyTo: draft.replyTo.isEmpty ? nil : draft.replyTo,
            updateTime: draft.updateTime
        )
    }

    /// «Избранное» и чаты без числового id на сервер не уходят.
    static func syncs(_ chatId: String) -> Bool {
        chatId != Chat.savedMessagesId && Int64(chatId) != nil
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// Ответы черновиков в памяти (тесты и запасной вариант).
private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: ServerSyncedDraftStore.ReplyMark] = [:]

    var value: [String: ServerSyncedDraftStore.ReplyMark] {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
