import Foundation

/// Чем занят собеседник: значение `type` пуша `NOTIF_TYPING` 129 и запроса `MSG_TYPING` 65.
/// Пустой, отсутствующий и незнакомый тип — обычный набор текста (`TEXT`).
public enum TypingKind: String, Hashable, Sendable, CaseIterable {
    /// Набирает текст.
    case text = "TEXT"
    /// Записывает голосовое.
    case audio = "AUDIO"
    /// Записывает видеосообщение (кружок).
    case videoMessage = "VIDEO_MSG"
    /// Отправляет фото.
    case photo = "PHOTO"
    /// Отправляет видео.
    case video = "VIDEO"
    /// Отправляет файл.
    case file = "FILE"
    /// Выбирает стикер.
    case sticker = "STICKER"

    /// Тип с сервера как есть.
    public init(raw: String?) {
        self = raw.flatMap(TypingKind.init(rawValue:)) ?? .text
    }
}

/// Один печатающий в чате.
public struct TypingActivity: Hashable, Sendable {
    public var userId: String
    /// `type` последнего пуша 129 как есть. `nil` — сервер его не прислал.
    public var type: String?
    /// Когда начал: первый пуш после паузы. По нему печатающие идут в строке по порядку.
    public var startedAt: Date
    /// Имя, которое приложение уже знает (из сохранённых сообщений). `nil` — неизвестно.
    public var name: String?

    public init(userId: String, type: String? = nil, startedAt: Date, name: String? = nil) {
        self.userId = userId
        self.type = type
        self.startedAt = startedAt
        self.name = name
    }

    public var kind: TypingKind { TypingKind(raw: type) }
}

/// Кто печатает: чистая логика сроков без таймеров и хранения.
///
/// Отметка живёт `ttl` после последнего пуша 129 этого пользователя (включительно, как
/// `MaxState.typingUsers` ядра): пуш в 0 с, срок 8 с — в 8 с ещё печатает, позже — нет.
/// Повторный пуш продлевает срок и заменяет тип, место в очереди сохраняется. Сообщение
/// пользователя снимает отметку сразу. Общие сценарии — `test-fixtures/typing`.
public struct TypingTracker: Sendable {
    /// Сколько держать отметку без нового пуша: 8 с, как у веб-клиента Max.
    public static let defaultTTL: TimeInterval = 8

    /// Время в миллисекундах: сравнение с границей срока не зависит от округления `Double`.
    private struct Entry: Sendable {
        var type: String?
        var startedAt: Int64
        var lastPush: Int64
    }

    public let ttl: TimeInterval
    private let ttlMs: Int64
    /// id чата → id пользователя → отметка.
    private var entries: [String: [String: Entry]] = [:]

    public init(ttl: TimeInterval = TypingTracker.defaultTTL) {
        self.ttl = ttl
        self.ttlMs = Int64((ttl * 1000).rounded())
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Пуш 129. Пустые id не учитываются.
    public mutating func note(chatId: String, userId: String, type: String?, at date: Date) {
        guard !chatId.isEmpty, !userId.isEmpty else { return }
        let normalized = type.flatMap { $0.isEmpty ? nil : $0 }
        let now = Self.millis(date)
        var users = entries[chatId] ?? [:]
        if var entry = users[userId], isAlive(entry, at: now) {
            entry.type = normalized
            entry.lastPush = now
            users[userId] = entry
        } else {
            users[userId] = Entry(type: normalized, startedAt: now, lastPush: now)
        }
        entries[chatId] = users
    }

    /// Сообщение от `userId`: он больше не печатает. `true`, если отметка была.
    @discardableResult
    public mutating func stop(chatId: String, userId: String) -> Bool {
        guard entries[chatId]?[userId] != nil else { return false }
        entries[chatId]?[userId] = nil
        if entries[chatId]?.isEmpty == true { entries[chatId] = nil }
        return true
    }

    /// Снимает истёкшие отметки. `true`, если что-то снято.
    @discardableResult
    public mutating func expire(at date: Date) -> Bool {
        let now = Self.millis(date)
        var changed = false
        for (chatId, users) in entries {
            let alive = users.filter { isAlive($0.value, at: now) }
            guard alive.count != users.count else { continue }
            changed = true
            entries[chatId] = alive.isEmpty ? nil : alive
        }
        return changed
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// Живые отметки на момент `date`: id чата → печатающие по времени начала
    /// (при равенстве — по id). Чатов без печатающих в словаре нет.
    public func snapshot(at date: Date) -> [String: [TypingActivity]] {
        let now = Self.millis(date)
        var result: [String: [TypingActivity]] = [:]
        for (chatId, users) in entries {
            var list: [TypingActivity] = []
            for (userId, entry) in users where isAlive(entry, at: now) {
                let started = Date(timeIntervalSince1970: TimeInterval(entry.startedAt) / 1000)
                list.append(TypingActivity(userId: userId, type: entry.type, startedAt: started))
            }
            if !list.isEmpty { result[chatId] = Self.ordered(list) }
        }
        return result
    }

    /// Порядок строки: кто начал раньше, тот первый.
    public static func ordered(_ list: [TypingActivity]) -> [TypingActivity] {
        list.sorted { left, right in
            if left.startedAt != right.startedAt { return left.startedAt < right.startedAt }
            return left.userId < right.userId
        }
    }

    private func isAlive(_ entry: Entry, at now: Int64) -> Bool {
        now - entry.lastPush <= ttlMs
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
