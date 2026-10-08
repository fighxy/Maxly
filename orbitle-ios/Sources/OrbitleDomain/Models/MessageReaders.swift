import Foundation

/// Один человек в разделе «Кем прочитано».
public struct MessageReader: Hashable, Sendable, Identifiable {
    public var userId: String
    /// Эмодзи реакции из `MSG_GET_DETAILED_REACTIONS` 181. `nil` — прочитал без реакции.
    public var reaction: String?
    /// Отметка прочтения (мс): время последнего прочитанного сообщения, а не момент чтения.
    /// `nil` — в списке только из-за реакции, известная отметка раньше сообщения или её нет.
    public var readMark: Int64?
    /// Имя для строки. Пустое — профиль неизвестен.
    public var name: String
    public var avatarURL: URL?

    public var id: String { userId }

    public init(userId: String, reaction: String? = nil, readMark: Int64? = nil, name: String = "", avatarURL: URL? = nil) {
        self.userId = userId
        self.reaction = reaction
        self.readMark = readMark
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// Строка прочтения своего сообщения в личном чате на экране сведений.
public enum PrivateReadStatus: String, Hashable, Sendable {
    case read
    case delivered

    public var title: String {
        switch self {
        case .read: "Прочитано"
        case .delivered: "Доставлено"
        }
    }
}

/// «Кем прочитано»: чистые правила без сети и хранения.
///
/// Отдельного запроса в протоколе нет. Список собирается из отметок прочтения участников
/// (`participants` карточки чата: id → время в мс, поверх — пуши `NOTIF_MARK` 130) и реакций
/// (`MSG_GET_DETAILED_REACTIONS` 181): отреагировавший тоже прочитал. Общие с Kotlin сценарии
/// и правила — `test-fixtures/readers`.
public enum MessageReaders {
    /// Порог участников, если сервер не прислал `max-readmarks`.
    public static let defaultMaxReadmarks = 100

    /// Состояние сообщения для правил экрана.
    public enum MessageState: String, Hashable, Sendable {
        case sent
        case sending
        case failed
        case scheduled
    }

    /// Одна запись ответа 181.
    public struct Reaction: Hashable, Sendable {
        public var userId: String
        public var emoji: String

        public init(userId: String, emoji: String) {
            self.userId = userId
            self.emoji = emoji
        }
    }

    /// Порог из серверного конфига (`max-readmarks`); нет его или он не больше нуля — 100.
    public static func maxReadmarks(server: Int?) -> Int {
        guard let server, server > 0 else { return defaultMaxReadmarks }
        return server
    }

    /// Показывать ли «Кем прочитано»: группа `CHAT` (не видеоконференция) не больше
    /// [maxReadmarks] участников и отправленное сообщение, своё или чужое. В личных чатах,
    /// «Избранном», каналах и комментариях списка нет. Участников считает `participantsCount`,
    /// а если его нет (`0`) — размер `participants` ([listedParticipants]), как в ядре.
    public static func isAvailable(
        chatId: String,
        chatType: String,
        isVideoConversation: Bool,
        participantsCount: Int,
        listedParticipants: Int = 0,
        messageState: MessageState,
        maxReadmarks: Int = defaultMaxReadmarks
    ) -> Bool {
        guard chatType.uppercased() == "CHAT", !isVideoConversation, chatId != Chat.savedMessagesId else { return false }
        let members = participantsCount > 0 ? participantsCount : listedParticipants
        guard members <= maxReadmarks else { return false }
        return messageState == .sent
    }

    /// Отметки участников: `participants` карточки чата (ключи и значения — числа или строки)
    /// и пуши 130. Из двух отметок одного пользователя побеждает бо́льшая. Записи, где id или
    /// отметка не число, пропускаются.
    public static func marks(participants: [AnyHashable: Any]?, pushed: [String: Int64] = [:]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for (key, value) in participants ?? [:] {
            guard let id = userId(key.base), let mark = number(value) else { continue }
            result[id] = max(result[id] ?? mark, mark)
        }
        return merged(result, pushed)
    }

    /// Две карты отметок вместе: для каждого пользователя бо́льшая.
    public static func merged(_ marks: [String: Int64], _ other: [String: Int64]) -> [String: Int64] {
        marks.merging(other) { max($0, $1) }
    }

    /// Список «Кем прочитано».
    ///
    /// Сначала отреагировавшие в порядке ответа 181 (с эмодзи), затем прочитавшие без реакции
    /// (`messageTime <= mark`) по убыванию отметки, при равной — по id как числу. Каждый один
    /// раз; себя ([me]) и автора ([authorId]) нет. У отреагировавшего `readMark` — его отметка,
    /// если она не раньше сообщения, иначе `nil`. `reactions == nil` — запрос 181 не удался:
    /// только прочитавшие.
    public static func build(
        messageTime: Int64,
        authorId: String?,
        me: String?,
        marks: [String: Int64],
        reactions: [Reaction]?
    ) -> [MessageReader] {
        var excluded = Set([authorId, me].compactMap { $0 })
        var result: [MessageReader] = []
        for reaction in reactions ?? [] {
            guard !reaction.userId.isEmpty, !reaction.emoji.isEmpty, !excluded.contains(reaction.userId) else { continue }
            excluded.insert(reaction.userId)
            let mark = marks[reaction.userId].flatMap { messageTime <= $0 ? $0 : nil }
            result.append(MessageReader(userId: reaction.userId, reaction: reaction.emoji, readMark: mark))
        }
        let readers = marks
            .filter { !excluded.contains($0.key) && messageTime <= $0.value }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : idLess(lhs.key, rhs.key)
            }
        result += readers.map { MessageReader(userId: $0.key, readMark: $0.value) }
        return result
    }

    /// Строка «Прочитано»/«Доставлено» для своего отправленного сообщения в личном чате
    /// (не «Избранное»): прочитано, если отметка собеседника больше нуля и не раньше времени
    /// сообщения. В остальных случаях `nil`.
    public static func privateStatus(
        chatId: String,
        chatType: String,
        isOwn: Bool,
        messageState: MessageState,
        messageTime: Int64,
        peerMark: Int64
    ) -> PrivateReadStatus? {
        guard chatType.uppercased() == "DIALOG", chatId != Chat.savedMessagesId, isOwn, messageState == .sent else { return nil }
        return peerMark > 0 && peerMark >= messageTime ? .read : .delivered
    }

    // MARK: Разбор

    /// id пользователя из числа или строки с числом.
    public static func userId(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return Int64(trimmed).map(String.init)
        }
        return integer(value).map(String.init)
    }

    /// Отметка из числа или строки с числом.
    static func number(_ value: Any?) -> Int64? {
        if let string = value as? String {
            return Int64(string.trimmingCharacters(in: .whitespaces))
        }
        return integer(value)
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            // JSON `true`/`false` — тоже NSNumber (тип `c`), но это не id и не время.
            if String(cString: number.objCType) == "c" { return nil }
            let double = number.doubleValue
            guard double.rounded() == double, abs(double) < 9.0e18 else { return nil }
            return number.int64Value
        }
        switch value {
        case let int as Int: return Int64(int)
        case let int as Int64: return int
        case let int as Int32: return Int64(int)
        default: return nil
        }
    }

    /// id по возрастанию как числа; если не числа — как строки.
    static func idLess(_ lhs: String, _ rhs: String) -> Bool {
        if let left = Int64(lhs), let right = Int64(rhs) { return left < right }
        return lhs < rhs
    }
}

/// Правила экрана сведений о сообщении, кроме «Кем прочитано».
public enum MessageInfo {
    /// Время правки для строки «изменено»: `updateTime` сообщения (мс). `nil` или `0` (так его
    /// отдаёт мост, если правки не было) — не изменялось.
    public static func editedTime(updateTime: Int64?) -> Int64? {
        guard let updateTime, updateTime > 0 else { return nil }
        return updateTime
    }
}
