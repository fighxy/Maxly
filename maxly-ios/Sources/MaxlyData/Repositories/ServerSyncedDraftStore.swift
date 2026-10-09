import Foundation
import MaxlyDomain

/// Черновики устройства, сверенные с черновиками сервера (`DRAFT_SAVE` 176, `DRAFT_DISCARD` 177).
///
/// При открытии чата что показать решает ядро (`reconcileDraft`, правило test-fixtures/drafts:
/// более новый, стирание не раньше него стирает); итог записывается на устройство. Пока
/// печатают, черновик живёт только на устройстве; серверу он уходит, когда из чата ушли (`commitDraft`): непустой — сохраняется,
/// пустой при черновике на сервере — стирается там. Черновик из одного ответа (без текста) —
/// тоже черновик. Вложения в черновик не попадают никогда. После отправки черновик стирает
/// ядро, порядок 176/177 в чате тоже держит ядро. Черновики с других устройств и метки
/// стирания приходят событиями `draft` (`serverDraftChanged`).
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
    /// Текст, взятый с сервера, и его время на сервере: запись в базу ставит время устройства,
    /// а сверять такой черновик надо по серверному.
    private var adopted: [String: (text: String, time: Int64)] = [:]
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

    /// Поле ввода при открытии чата: свой черновик сверяет ядро (`reconcileDraft`) с черновиком
    /// сервера и меткой стирания. Итог записывается на устройство.
    public func draft(chatId: String) async -> String? {
        let mine = await local.draft(chatId: chatId)
        guard Self.syncs(chatId) else { return mine }
        return await reconcile(chatId).text
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
        let server = await core.serverDrafts().first { $0.chatId == chatId }.map(Self.synced)
        switch DraftSync.request(local: device, server: server, address: .chat(chatId)) {
        case let .save(_, text, elements, replyTo):
            do {
                // `0` без ошибки: сохранение перекрыла отправка, черновика больше нет.
                _ = try await core.saveDraft(
                    chatId: chatId, text: text, elementsJSON: MessageMarkup.json(elements), replyTo: replyTo ?? ""
                )
            } catch {
                Log.warning(.messages, "Черновик не сохранён на сервере: \(error)")
            }
        case let .discard(_, serverTime):
            do {
                try await core.discardDraft(chatId: chatId, time: serverTime)
            } catch {
                Log.warning(.messages, "Черновик не стёрт на сервере: \(error)")
            }
        case nil:
            break
        }
    }

    /// Черновик или метка стирания сервера изменились (событие `draft` ядра: другое
    /// устройство, пуши 152/153, отправка). Черновик устройства сверяется заново; если он
    /// поменялся, экран чата узнаёт об этом из `draftChanges`.
    public func serverDraftChanged(chatId: String) async {
        guard Self.syncs(chatId) else { return }
        let before = (await local.draft(chatId: chatId), replies[chatId]?.messageId)
        let after = await reconcile(chatId)
        guard before.0 != after.text || before.1 != after.reply else { return }
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

    /// Сверка ядром и запись итога на устройство: текст в базу, ответ — в `replies`.
    private func reconcile(_ chatId: String) async -> (text: String?, reply: String?) {
        let mine = await local.draft(chatId: chatId)
        let device = await deviceDraft(chatId)
        let result = await core.reconcileDraft(
            chatId: chatId,
            text: device?.text ?? "",
            elementsJSON: "[]",
            replyTo: device?.replyTo ?? "",
            updateTime: device?.updateTime ?? 0
        )
        let text = result.flatMap { $0.text.isEmpty ? nil : $0.text }
        if text != mine {
            await local.saveDraft(text ?? "", chatId: chatId)
            adopted[chatId] = text.map { (text: $0, time: result?.updateTime ?? 0) }
        }
        let reply = result.flatMap { $0.replyTo.isEmpty ? nil : $0.replyTo }
        if reply != replies[chatId]?.messageId {
            setReply(reply.map { ReplyMark(messageId: $0, time: result?.updateTime ?? 0) }, chatId: chatId)
        }
        return (text, reply)
    }

    /// Черновик устройства: текст из базы и ответ; время — позднее из двух.
    private func deviceDraft(_ chatId: String) async -> SyncedDraft? {
        let text = await local.draft(chatId: chatId) ?? ""
        let reply = replies[chatId]
        guard !text.isEmpty || reply != nil else { return nil }
        var textTime = await local.draftTime(chatId: chatId).map(Self.millis) ?? 0
        if let mark = adopted[chatId], mark.text == text { textTime = mark.time }
        return SyncedDraft(text: text, replyTo: reply?.messageId, updateTime: max(textTime, reply?.time ?? 0))
    }

    private func setReply(_ mark: ReplyMark?, chatId: String) {
        replies[chatId] = mark
        storage.store(replies)
    }

    static func synced(_ draft: CoreDraft) -> SyncedDraft {
        SyncedDraft(
            text: draft.text,
            spans: MessageMarkup.parse(json: draft.elementsJSON, text: draft.text),
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
