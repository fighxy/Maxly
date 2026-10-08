import Foundation
import OrbitleDomain

/// Черновики устройства, сверенные с черновиками сервера (`DRAFT_SAVE` 176, `DRAFT_DISCARD` 177).
///
/// При открытии чата побеждает более новый из двух (`DraftSync.merge`, test-fixtures/drafts);
/// черновик сервера записывается на устройство. Пока печатают, черновик живёт только на
/// устройстве; серверу он уходит, когда из чата ушли (`commitDraft`): непустой — сохраняется,
/// пустой при черновике на сервере — стирается там. Ядро не хранит черновики между запусками,
/// поэтому их память на устройстве — локальная база.
///
/// На сервер уходит только текст: разметку и цитату черновика база устройства пока не хранит.
public actor ServerSyncedDraftStore: ChatDraftStore {
    private let local: any ChatDraftStore
    private let core: any MaxCore
    /// Последний известный черновик сервера по чату (из ядра или своего сохранения).
    private var known: [String: SyncedDraft] = [:]

    public init(local: any ChatDraftStore, core: any MaxCore) {
        self.local = local
        self.core = core
    }

    public func draft(chatId: String) async -> String? {
        let mine = await local.draft(chatId: chatId)
        guard Self.syncs(chatId) else { return mine }
        let time = await local.draftTime(chatId: chatId)
        let device = mine.map { SyncedDraft(text: $0, updateTime: time.map(Self.millis) ?? 0) }
        let server = await serverDraft(chatId)
        guard let winner = DraftSync.merge(local: device, server: server, discardedAt: nil) else { return mine }
        if winner.text != mine {
            await local.saveDraft(winner.text, chatId: chatId)
        }
        return winner.text
    }

    public func saveDraft(_ text: String, chatId: String) async {
        await local.saveDraft(text, chatId: chatId)
    }

    public func draftTime(chatId: String) async -> Date? {
        await local.draftTime(chatId: chatId)
    }

    public func commitDraft(chatId: String) async {
        guard Self.syncs(chatId) else { return }
        let text = await local.draft(chatId: chatId) ?? ""
        let time = await local.draftTime(chatId: chatId).map(Self.millis) ?? 0
        let device = SyncedDraft(text: text, updateTime: time)
        let server = await serverDraft(chatId)
        switch DraftSync.request(local: device, server: server, address: .chat(chatId)) {
        case let .save(_, text, elements, replyTo):
            do {
                let saved = try await core.saveDraft(
                    chatId: chatId, text: text, elementsJSON: MessageMarkup.json(elements), replyTo: replyTo ?? ""
                )
                known[chatId] = SyncedDraft(text: text, replyTo: replyTo, updateTime: saved > 0 ? saved : time)
            } catch {
                Log.warning(.messages, "Черновик не сохранён на сервере: \(error)")
            }
        case let .discard(_, serverTime):
            do {
                try await core.discardDraft(chatId: chatId, time: serverTime)
                known[chatId] = nil
            } catch {
                Log.warning(.messages, "Черновик не стёрт на сервере: \(error)")
            }
        case nil:
            break
        }
    }

    /// Черновик сервера: из ядра (вход и пуши) или своё последнее сохранение — что новее.
    private func serverDraft(_ chatId: String) async -> SyncedDraft? {
        let fromCore = await core.serverDrafts().first { $0.chatId == chatId }.map(Self.synced)
        switch (fromCore, known[chatId]) {
        case let (core?, mine?): return core.updateTime >= mine.updateTime ? core : mine
        case let (core?, nil): return core
        case let (nil, mine): return mine
        }
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
