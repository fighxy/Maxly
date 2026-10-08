import Foundation

/// Выбор нескольких сообщений: удаление, пересылка и копирование. Общие с Kotlin сценарии —
/// `test-fixtures/selection`.
public enum MessageSelectionRules {
    // MARK: Удаление

    /// Как можно удалить одно сообщение.
    public enum DeleteScope: String, Hashable, Sendable {
        /// У всех (или только у всех — в канале).
        case all
        /// Только у себя.
        case `self`
        /// Нельзя.
        case none
    }

    /// Срок, в который своё сообщение можно удалить у всех (`edit-timeout` сервера, секунды).
    public enum EditTimeout: Hashable, Sendable {
        /// Значение конфига сервера. Нет ключа — 0 (как в веб-клиенте): у всех нельзя.
        case seconds(Int)
        /// Клиент конфига не видит вовсе (мост ядра его пока не отдаёт): своё отправленное
        /// удаляется у всех без срока, как было до этих правил. В сценариях не встречается.
        case unknown

        public static func server(_ value: Int?) -> EditTimeout { .seconds(max(value ?? 0, 0)) }
    }

    /// Сообщение для правил удаления.
    public struct Item: Hashable, Sendable {
        public var id: String
        public var isOwn: Bool
        /// Принято сервером (есть серверный id, не `sending`/`failed`).
        public var isSent: Bool
        public var time: Date

        public init(id: String, isOwn: Bool, isSent: Bool, time: Date) {
            self.id = id
            self.isOwn = isOwn
            self.isSent = isSent
            self.time = time
        }
    }

    /// Чат для правил удаления.
    public struct ChatContext: Hashable, Sendable {
        public var id: String
        public var type: ChatType
        /// Аккаунт — владелец или админ с правом удалять чужие сообщения.
        public var isAdmin: Bool

        public init(id: String, type: ChatType, isAdmin: Bool) {
            self.id = id
            self.type = type
            self.isAdmin = isAdmin
        }

        public var isSavedMessages: Bool { id == Chat.savedMessagesId }
    }

    /// - «Избранное»: только у себя (на деле сообщение стирается на сервере целиком, выбора нет).
    /// - Неотправленное: только у себя (стирается на устройстве).
    /// - Личный чат: своё в пределах `edit-timeout` — у всех, иначе у себя.
    /// - Группа: админ — у всех; своё в пределах `edit-timeout` — у всех; иначе у себя.
    /// - Канал: админ — у всех (и только так), остальные — нельзя.
    public static func scope(of item: Item, in chat: ChatContext, timeout: EditTimeout, now: Date) -> DeleteScope {
        if chat.isSavedMessages { return .self }
        if !item.isSent { return chat.type == .channel && !chat.isAdmin ? .none : .self }
        let fresh: Bool
        switch timeout {
        case .unknown: fresh = true
        case .seconds(let seconds): fresh = seconds > 0 && now.timeIntervalSince(item.time) < Double(seconds)
        }
        switch chat.type {
        case .private:
            return item.isOwn && fresh ? .all : .self
        case .group:
            if chat.isAdmin { return .all }
            return item.isOwn && fresh ? .all : .self
        case .channel:
            return chat.isAdmin ? .all : .none
        }
    }

    /// Что показать в подтверждении удаления выбранных сообщений.
    public struct DeleteOptions: Hashable, Sendable {
        /// Кнопка «Удалить» доступна: ни одно сообщение не «нельзя».
        public var canDelete: Bool
        /// Переключатель «Удалить у всех»: все сообщения можно у всех, и это не канал.
        public var showsForEveryone: Bool
        /// Удаление только у всех, без выбора (канал).
        public var forcesForEveryone: Bool
        /// Начальное положение переключателя (включён, как в веб-клиенте).
        public var forEveryoneByDefault: Bool
    }

    public static func deleteOptions(_ items: [Item], in chat: ChatContext, timeout: EditTimeout, now: Date) -> DeleteOptions {
        let scopes = items.map { scope(of: $0, in: chat, timeout: timeout, now: now) }
        let canDelete = !scopes.isEmpty && !scopes.contains(.none)
        let allForEveryone = canDelete && scopes.allSatisfy { $0 == .all }
        let forced = allForEveryone && chat.type == .channel
        let toggle = allForEveryone && !forced
        return DeleteOptions(canDelete: canDelete, showsForEveryone: toggle, forcesForEveryone: forced, forEveryoneByDefault: toggle)
    }

    // MARK: Пересылка

    /// Один запрос пересылки: комментарий или одно сообщение в один чат.
    public enum ForwardStep: Hashable, Sendable {
        case comment(target: String, text: String)
        case message(target: String, messageId: String)
    }

    /// Порядок запросов: сначала комментарий (если есть) в каждый чат, затем каждое сообщение
    /// от старых к новым — в каждый чат по порядку выбора. Один запрос на сообщение на чат.
    public static func forwardPlan(messages: [(id: String, time: Date)], targets: [String], comment: String?) -> [ForwardStep] {
        var steps: [ForwardStep] = []
        var seenTargets = Set<String>()
        let targets = targets.filter { seenTargets.insert($0).inserted }
        if let text = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            steps += targets.map { .comment(target: $0, text: text) }
        }
        var seenIds = Set<String>()
        let ordered = messages
            .filter { seenIds.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time < rhs.time }
                return idOrder(lhs.id, rhs.id)
            }
        for message in ordered {
            steps += targets.map { .message(target: $0, messageId: message.id) }
        }
        return steps
    }

    // MARK: Копирование

    /// Сообщение для копирования.
    public struct CopyItem: Hashable, Sendable {
        public var id: String
        public var time: Date
        public var authorName: String
        public var text: String
        /// Подпись вложения для сообщения без текста («Фото», «Стикер»…).
        public var placeholder: String

        public init(id: String, time: Date, authorName: String, text: String, placeholder: String) {
            self.id = id
            self.time = time
            self.authorName = authorName
            self.text = text
            self.placeholder = placeholder
        }
    }

    /// Одно сообщение — просто его текст. Несколько — от старых к новым блоки
    /// «Имя, [дд.мм.гггг чч:мм]\nтекст» через пустую строку. Без текста — подпись вложения;
    /// без имени — «Участник». Время — в поясе [timeZone].
    public static func copyText(_ items: [CopyItem], timeZone: TimeZone) -> String {
        let ordered = items.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return idOrder(lhs.id, rhs.id)
        }
        func body(_ item: CopyItem) -> String {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? item.placeholder : text
        }
        if ordered.count == 1 { return body(ordered[0]) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ordered.map { item in
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.time)
            let stamp = String(format: "%02d.%02d.%04d %02d:%02d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0, parts.hour ?? 0, parts.minute ?? 0)
            let name = item.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name.isEmpty ? DisplayName.fallback : name), [\(stamp)]\n\(body(item))"
        }.joined(separator: "\n\n")
    }

    /// Подпись сообщения без текста по первому вложению — те же слова, что в списке чатов.
    public static func placeholder(for media: MessageMediaKind?) -> String {
        switch media {
        case .photo: "Фото"
        case .video: "Видео"
        case .videoMessage: "Видеосообщение"
        case .voice, .audio: "Голосовое сообщение"
        case .file: "Файл"
        case .sticker: "Стикер"
        case .gif: "GIF"
        case .location: "Геопозиция"
        case .contact: "Контакт"
        case .poll: "Опрос"
        case .call: "Звонок"
        case .groupCall: "Групповой звонок"
        case nil: "Сообщение"
        }
    }

    /// Равное время — по серверному id как числу, затем как строке.
    public static func idOrder(_ lhs: String, _ rhs: String) -> Bool {
        switch (Int64(lhs), Int64(rhs)) {
        case let (l?, r?): l < r
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): lhs < rhs
        }
    }
}
