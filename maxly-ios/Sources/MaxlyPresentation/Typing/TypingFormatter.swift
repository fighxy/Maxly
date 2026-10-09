import Foundation
import MaxlyDomain

/// Текст «кто чем занят» для строки списка и шапки чата. Чистые правила, общие с Kotlin
/// (`test-fixtures/typing`, раздел «Тексты»).
///
/// - Личный чат: только действие («печатает…»).
/// - Группа: тип берётся у того, кто начал раньше всех; в строке только те, у кого тот же тип,
///   по времени начала. Имена: «Иван», «Иван и Петя», «Иван, Петя и Маша», «Иван и ещё 3».
///   Глагол в единственном числе только для одного человека.
/// - Нужного имени нет — счёт («2 участника печатают…»), один без имени — только действие.
/// - Канал и пустой список — `nil`.
public enum TypingFormatter {
    /// Печатающий для текста: имя (только имя, без фамилии) и тип как есть.
    public struct Participant: Hashable, Sendable {
        public var name: String?
        public var type: String?

        public init(name: String? = nil, type: String? = nil) {
            self.name = name
            self.type = type
        }

        public var kind: TypingKind { TypingKind(raw: type) }
    }

    /// Строка списка чатов, с «…» в конце. `participants` — по времени начала.
    public static func text(chatType: ChatType, participants: [Participant]) -> String? {
        guard chatType != .channel, let first = participants.first else { return nil }
        let kind = first.kind
        guard chatType == .group else { return verb(kind, plural: false) + "…" }
        let same = participants.filter { $0.kind == kind }
        return groupText(kind: kind, names: same.map { firstName($0.name) }) + "…"
    }

    /// Шапка чата: тот же текст без «…» — точки рисует экран.
    public static func headerText(chatType: ChatType, participants: [Participant]) -> String? {
        guard let text = text(chatType: chatType, participants: participants) else { return nil }
        return text.hasSuffix("…") ? String(text.dropLast()) : text
    }

    /// Печатающие репозитория в порядке начала. Имя из `names` (id → имя) важнее имени,
    /// сохранённого с сообщениями.
    public static func participants(_ activities: [TypingActivity], names: [String: String] = [:]) -> [Participant] {
        activities.map { Participant(name: names[$0.userId] ?? $0.name, type: $0.type) }
    }

    /// Действие: «печатает» / «печатают».
    public static func verb(_ kind: TypingKind, plural: Bool) -> String {
        switch kind {
        case .text: plural ? "печатают" : "печатает"
        case .audio: plural ? "записывают аудио" : "записывает аудио"
        case .videoMessage: plural ? "записывают видеосообщение" : "записывает видеосообщение"
        case .photo: plural ? "отправляют фото" : "отправляет фото"
        case .video: plural ? "отправляют видео" : "отправляет видео"
        case .file: plural ? "отправляют файл" : "отправляет файл"
        case .sticker: plural ? "выбирают стикер" : "выбирает стикер"
        }
    }

    /// Счёт без имён: «2 участника печатают», «21 участник печатает».
    public static func countText(_ count: Int, kind: TypingKind) -> String {
        let tens = count % 100
        let ones = count % 10
        let noun: String
        if (11...14).contains(tens) {
            noun = "участников"
        } else {
            switch ones {
            case 1: noun = "участник"
            case 2...4: noun = "участника"
            default: noun = "участников"
            }
        }
        let singular = ones == 1 && tens != 11
        return "\(count) \(noun) \(verb(kind, plural: !singular))"
    }

    /// Имя без фамилии: первое слово. Пустое — `nil`.
    public static func firstName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let word = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        return String(word)
    }

    private static func groupText(kind: TypingKind, names: [String?]) -> String {
        let count = names.count
        // Сколько имён нужно для подписи: до трёх — все, дальше — только первое.
        let needed = count <= 3 ? names : Array(names.prefix(1))
        let known = needed.compactMap { $0 }
        guard known.count == needed.count else {
            return count == 1 ? verb(kind, plural: false) : countText(count, kind: kind)
        }
        let who: String
        switch count {
        case 1: who = known[0]
        case 2: who = "\(known[0]) и \(known[1])"
        case 3: who = "\(known[0]), \(known[1]) и \(known[2])"
        default: who = "\(known[0]) и ещё \(count - 1)"
        }
        return "\(who) \(verb(kind, plural: count > 1))"
    }
}
