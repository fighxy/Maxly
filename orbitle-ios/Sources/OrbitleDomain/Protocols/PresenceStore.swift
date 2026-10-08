import Foundation

/// Куда писать статус «в сети»: карточки и контакты сейчас, пуш присутствия ядра потом.
public protocol PresenceSink: Sendable {
    /// Статусы по id пользователя, узнанные в момент `at`.
    func record(_ batch: [String: Contact.Presence], at date: Date) async
}

/// Статус «в сети» для экранов: спросить сервер о видимых людях и узнать об изменениях.
public protocol PresenceProvider: Sendable {
    /// Спросить статусы этих людей (видимые диалоги, контакты, участники, профиль). Тех, кого
    /// спрашивали недавно, источник пропускает сам. Ответ приходит через `changes()`.
    func refresh(_ userIds: [String]) async
    /// Последний известный статус; `nil` — о человеке ничего не известно.
    func presence(of userId: String) async -> Contact.Presence?
    /// Id людей, чей статус изменился.
    func changes() -> AsyncStream<Set<String>>
}

/// Последний известный статус «в сети» по id пользователя, общий для экранов.
///
/// Правила:
/// - `.unknown` известное значение не затирает: сервер просто ничего не сказал;
/// - запись старше уже известной (по времени `at`) не применяется;
/// - «в сети» живёт `onlineTTL` секунд (как `presence-ttl` сервера, 5 минут). Без подтверждения
///   оно становится «был(а)» во время последнего подтверждения, а не висит вечно.
public actor PresenceStore: PresenceSink {
    public static let defaultOnlineTTL: TimeInterval = 300

    private struct Entry {
        var presence: Contact.Presence
        var at: Date
    }

    private let onlineTTL: TimeInterval
    private var entries: [String: Entry] = [:]
    private var observers: [UUID: AsyncStream<Set<String>>.Continuation] = [:]

    public init(onlineTTL: TimeInterval = PresenceStore.defaultOnlineTTL) {
        self.onlineTTL = onlineTTL
    }

    public func record(_ batch: [String: Contact.Presence], at date: Date = Date()) {
        var changed = Set<String>()
        for (userId, presence) in batch where !userId.isEmpty && presence != .unknown {
            if let known = entries[userId], known.at > date { continue }
            if entries[userId]?.presence != presence { changed.insert(userId) }
            entries[userId] = Entry(presence: presence, at: date)
        }
        guard !changed.isEmpty else { return }
        observers.values.forEach { $0.yield(changed) }
    }

    public func record(_ presence: Contact.Presence, userId: String, at date: Date = Date()) {
        record([userId: presence], at: date)
    }

    /// Статус на момент `now`; `nil`, если о человеке ничего не известно.
    public func presence(of userId: String, now: Date = Date()) -> Contact.Presence? {
        guard let entry = entries[userId] else { return nil }
        if entry.presence == .online, now.timeIntervalSince(entry.at) > onlineTTL {
            return .lastSeen(entry.at)
        }
        return entry.presence
    }

    public func isOnline(_ userId: String, now: Date = Date()) -> Bool {
        presence(of: userId, now: now) == .online
    }

    /// Выход из аккаунта: статусы прежнего сеанса не переносятся.
    public func removeAll() {
        entries.removeAll()
    }

    /// Id людей, чей статус изменился.
    public nonisolated func changes() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    private func addObserver(_ id: UUID, _ continuation: AsyncStream<Set<String>>.Continuation) {
        observers[id] = continuation
        // Подписка доходит до хранилища отдельной задачей. Статус, записанный в этот зазор,
        // иначе теряется: новый подписчик получает уже известные id и читает их сам.
        let known = Set(entries.keys)
        if !known.isEmpty { continuation.yield(known) }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
