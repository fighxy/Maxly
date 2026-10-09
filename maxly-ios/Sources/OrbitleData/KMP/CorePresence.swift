import Foundation
import OrbitleDomain

/// Статус человека от ядра: `status` — `-1` неизвестно, `0` не в сети (`seenMs` — последний
/// визит), `1` в сети, `2` недавно (время скрыто), `3` давно; `seenMs` `0` — времени нет.
public struct CorePresence: Sendable, Equatable {
    public var userId: String
    public var status: Int
    public var seenMs: Int64

    public init(userId: String, status: Int, seenMs: Int64 = 0) {
        self.userId = userId
        self.status = status
        self.seenMs = seenMs
    }

    /// Статус для экранов (`test-fixtures/presence`).
    public var presence: Contact.Presence {
        Contact.Presence.server(status: status, seenMs: seenMs)
    }
}

/// Ядро без статусов: ничего не известно, спрашивать нечего.
public extension MaxCore {
    func loadPresence(userIds: [String]) async throws -> [CorePresence] { [] }
    func presenceOf(userId: String) async -> CorePresence { CorePresence(userId: userId, status: -1) }
    func setAppActive(_ active: Bool) async {}
}

/// Статусы через ядро: спрашивает видимых людей не чаще раза в `minGap` на человека, пишет
/// ответы в общий `PresenceStore`; события `presence` туда же пишет `SyncEngine`.
public actor CorePresenceService: PresenceProvider {
    private let core: any MaxCore
    private let store: PresenceStore
    private let minGap: TimeInterval
    private let now: @Sendable () -> Date
    private var asked: [String: Date] = [:]

    public init(core: any MaxCore, store: PresenceStore, minGap: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.core = core
        self.store = store
        self.minGap = minGap
        self.now = now
    }

    public func refresh(_ userIds: [String]) async {
        let date = now()
        var seen = Set<String>()
        let fresh = userIds.filter { id in
            guard Int64(id) != nil, seen.insert(id).inserted else { return false }
            if let last = asked[id], date.timeIntervalSince(last) < minGap { return false }
            return true
        }
        guard !fresh.isEmpty else { return }
        for id in fresh { asked[id] = date }
        do {
            let list = try await core.loadPresence(userIds: fresh)
            var batch: [String: Contact.Presence] = [:]
            for item in list { batch[item.userId] = item.presence }
            await store.record(batch, at: now())
        } catch {
            // Не вышло — спросить снова при следующем показе.
            for id in fresh { asked[id] = nil }
            Log.warning(.contacts, "Статусы не загружены: \(error)")
        }
    }

    /// Из общего хранилища; пусто — то, что держит ядро.
    public func presence(of userId: String) async -> Contact.Presence? {
        if let known = await store.presence(of: userId, now: now()) { return known }
        let core = await core.presenceOf(userId: userId)
        guard core.status >= 0, core.presence != .unknown else { return nil }
        await store.record(core.presence, userId: userId, at: now())
        return core.presence
    }

    public nonisolated func changes() -> AsyncStream<Set<String>> {
        store.changes()
    }

    /// Выход из аккаунта.
    public func reset() {
        asked.removeAll()
    }
}
