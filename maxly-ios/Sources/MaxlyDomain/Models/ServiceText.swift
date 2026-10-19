import Foundation

/// Текст служебного события чата (`ServiceNotice`) для ленты и строки списка чатов.
///
/// Автор события — отправитель сообщения. Свои события пишутся от «Вы», участник-аккаунт —
/// «вас». Имя, которого нет, заменяется словом «Участник» (или «Контакт» для «теперь в MAX»).
/// Название берётся в «ёлочки». Незнакомое событие без текста сервера — `fallback`.
public enum ServiceText {
    public static let fallback = "Служебное сообщение"

    /// - `actorId`, `actorName` — отправитель сообщения;
    /// - `outgoing` — сообщение своё (если вызывающий это знает); без него «своё» решает
    ///   `viewerId` события.
    public static func text(_ notice: ServiceNotice, actorId: String, actorName: String, outgoing: Bool? = nil) -> String {
        let viewer = notice.viewerId ?? ""
        let mine = outgoing ?? (!viewer.isEmpty && actorId == viewer)
        let actor = mine ? "Вы" : (clean(actorName) ?? clean(notice.names?[actorId]) ?? "Участник")
        func action(_ past: String, _ plural: String) -> String {
            mine ? "Вы \(plural)" : "\(actor) \(past)"
        }
        let title = clean(notice.title)
        let targets = notice.participantIds
        let onlyActor = targets.isEmpty || targets == [actorId]
        switch kind(notice) {
        case .joined:
            return joinedText(notice, actorId: actorId, actorName: actorName, mine: mine)
        case .created:
            let what = notice.chatType?.uppercased() == "CHANNEL" ? "канал" : "чат"
            let base = action("создал(а) \(what)", "создали \(what)")
            return title.map { "\(base) «\($0)»" } ?? base
        case .added:
            if onlyActor { return action("вступил(а) в чат", "вступили в чат") }
            return action("добавил(а)", "добавили") + " " + list(targets, notice: notice, actorId: actorId, actorName: actorName)
        case .removed:
            if targets.isEmpty { return action("удалил(а) участника", "удалили участника") }
            if targets == [actorId] { return action("покинул(а) чат", "покинули чат") }
            return action("удалил(а)", "удалили") + " " + list(targets, notice: notice, actorId: actorId, actorName: actorName)
        case .left:
            return action("покинул(а) чат", "покинули чат")
        case .joinedByLink:
            return action("вступил(а) в чат по ссылке", "вступили в чат по ссылке")
        case .renamed:
            guard let title else { return action("изменил(а) название чата", "изменили название чата") }
            return action("изменил(а) название на «\(title)»", "изменили название на «\(title)»")
        case .photo:
            return action("изменил(а) фото чата", "изменили фото чата")
        case .botStarted:
            return action("запустил(а) бота", "запустили бота")
        case .system, .unknown:
            return clean(notice.text) ?? title ?? fallback
        }
    }

    /// Текст служебного сообщения или `nil`, если `content` — не событие. `currentUserId` —
    /// аккаунт, когда событие сохранено без него.
    public static func text(of content: MessageContent, authorId: String, authorName: String, currentUserId: String = "") -> String? {
        guard var notice = content.service else { return nil }
        if notice.viewerId?.isEmpty != false, !currentUserId.isEmpty { notice.viewerId = currentUserId }
        return text(notice, actorId: authorId, actorName: authorName)
    }

    /// Вид события по `event` (без учёта регистра).
    public enum Kind: Equatable, Sendable {
        /// Контакт зарегистрировался: `hello` или `new` личного чата.
        case joined
        case created, added, removed, left, joinedByLink, renamed, photo, botStarted, system, unknown
    }

    public static func kind(_ notice: ServiceNotice) -> Kind {
        switch notice.event.lowercased() {
        case "hello": .joined
        case "new": notice.chatType?.uppercased() == "DIALOG" ? .joined : .created
        case "add": .added
        case "remove": .removed
        case "leave": .left
        case "joinbylink": .joinedByLink
        case "title": .renamed
        case "icon": .photo
        case "botstarted": .botStarted
        case "system": .system
        default: .unknown
        }
    }

    /// «<Имя> теперь в MAX»: имя того, о ком событие (`userId`, иначе отправитель).
    private static func joinedText(_ notice: ServiceNotice, actorId: String, actorName: String, mine: Bool) -> String {
        let subject = notice.participantIds.first ?? actorId
        let viewer = notice.viewerId ?? ""
        if (!viewer.isEmpty && subject == viewer) || (mine && subject == actorId) { return "Вы теперь в MAX" }
        let name = clean(notice.names?[subject]) ?? (subject == actorId ? clean(actorName) : nil) ?? "Контакт"
        return "\(name) теперь в MAX"
    }

    /// Участники через запятую и «и»; аккаунт — «вас», без имени — счётом.
    static func list(_ ids: [String], notice: ServiceNotice, actorId: String, actorName: String) -> String {
        let viewer = notice.viewerId ?? ""
        var names: [String] = []
        var unknown = 0
        for id in ids {
            if !viewer.isEmpty, id == viewer {
                names.append("вас")
            } else if let name = clean(notice.names?[id]) ?? (id == actorId ? clean(actorName) : nil) {
                names.append(name)
            } else {
                unknown += 1
            }
        }
        if names.isEmpty { return unknown == 1 ? "участника" : "\(unknown) \(participants(unknown))" }
        if unknown > 0 { return names.joined(separator: ", ") + " и ещё \(unknown)" }
        guard names.count > 1, let last = names.last else { return names[0] }
        return names.dropLast().joined(separator: ", ") + " и " + last
    }

    /// «2 участника», «5 участников», «21 участника» (винительный падеж).
    static func participants(_ count: Int) -> String {
        let tens = count % 100
        let ones = count % 10
        if (11...14).contains(tens) { return "участников" }
        return (1...4).contains(ones) ? "участника" : "участников"
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
