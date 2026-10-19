import Foundation

/// Текст служебного события чата (`ServiceNotice`) для ленты, строки списка чатов и уведомлений.
///
/// Текст пишет ядро (`IosControl.fallbackText`, в событии — `coreText`): сначала текст сервера,
/// затем свой текст известного события с «Вы» для аккаунта и именами из стора ядра. Так все
/// клиенты показывают одно и то же. Если ядру сказать нечего (`system`, незнакомое событие без
/// текста сервера) — текст сервера или самого сообщения, иначе `fallback`.
///
/// Без текста ядра (сообщение сохранено старой сборкой) строка пишется так же, как пишет ядро
/// (`controlFallbackText` ядра d5e8aed, сценарии `test-fixtures/service-messages`): только
/// чтобы не показывать `fallback` до перечитывания истории.
public enum ServiceText {
    public static let fallback = "Служебное сообщение"

    /// - `actorId`, `actorName` — отправитель сообщения;
    /// - `outgoing` — сообщение своё (если вызывающий это знает); без него «своё» решает
    ///   `viewerId` события.
    public static func text(_ notice: ServiceNotice, actorId: String, actorName: String, outgoing: Bool? = nil) -> String {
        if let core = clean(notice.coreText) { return core }
        return storedText(notice, actorId: actorId, actorName: actorName, outgoing: outgoing)
            ?? clean(notice.text)
            ?? fallback
    }

    /// Текст известного события без текста ядра, теми же словами, что у ядра. `nil` — событие
    /// ядру незнакомо (`system`, незнакомое): тогда текст сервера или `fallback`.
    static func storedText(_ notice: ServiceNotice, actorId: String, actorName: String, outgoing: Bool?) -> String? {
        let viewer = notice.viewerId ?? ""
        let sender: String? = actorId.isEmpty || actorId == "0" ? nil : actorId
        let mine = outgoing ?? (sender != nil && !viewer.isEmpty && sender == viewer)
        let name: (String) -> String? = { id in
            clean(notice.names?[id]) ?? (id == sender ? clean(actorName) : nil)
        }
        let actorLabel = sender.flatMap(name)
        func subject(_ past: String, _ plural: String) -> String? {
            if mine { return "Вы \(plural)" }
            return actorLabel.map { "\($0) \(past)" }
        }
        let title = clean(notice.title)
        let ids = notice.userIds.filter { !$0.isEmpty && $0 != "0" }
        let targets = ids.isEmpty ? [notice.userId].compactMap { $0 }.filter { !$0.isEmpty && $0 != "0" } : ids
        switch notice.event.lowercased() {
        case "new":
            let chatType = notice.chatType?.uppercased()
            if chatType == "DIALOG", !mine, let actorLabel { return "\(actorLabel) теперь в MAX" }
            let channel = chatType == "CHANNEL"
            let what = channel ? "канал" : "чат"
            if let made = subject("создал(а)", "создали") { return title.map { "\(made) \(what) «\($0)»" } ?? "\(made) \(what)" }
            if let title { return channel ? "Создан канал «\(title)»" : "Создан чат «\(title)»" }
            return channel ? "Канал создан" : "Чат создан"
        case "add", "remove":
            let add = notice.event.lowercased() == "add"
            if let sender, targets == [sender] {
                return add
                    ? subject("вступил(а) в чат", "вступили в чат") ?? "Участник вступил(а) в чат"
                    : subject("покинул(а) чат", "покинули чат") ?? "Участник покинул(а) чат"
            }
            guard let did = add ? subject("добавил(а)", "добавили") : subject("удалил(а)", "удалили") else {
                return add ? "Добавлены участники" : "Удалены участники"
            }
            return did + " " + list(targets, viewerId: viewer, name: name)
        case "leave":
            return subject("покинул(а) чат", "покинули чат") ?? "Участник покинул(а) чат"
        case "title":
            if let renamed = subject("изменил(а) название", "изменили название") {
                return title.map { "\(renamed) на «\($0)»" } ?? "\(renamed) чата"
            }
            return title.map { "Название чата изменено на «\($0)»" } ?? "Название чата изменено"
        case "icon":
            return subject("изменил(а) фото чата", "изменили фото чата") ?? "Фото чата изменено"
        case "joinbylink":
            return subject("вступил(а) в чат по ссылке", "вступили в чат по ссылке") ?? "Участник вступил(а) в чат по ссылке"
        case "hello":
            let who = notice.userId.flatMap { id -> String? in id.isEmpty || id == "0" ? nil : id } ?? sender
            if let who, (!viewer.isEmpty && who == viewer) || (mine && who == sender) { return "Вы теперь в MAX" }
            return who.flatMap(name).map { "\($0) теперь в MAX" } ?? "Контакт теперь в MAX"
        case "botstarted":
            return mine ? "Вы запустили бота" : "Бот запущен"
        default:
            return nil
        }
    }

    /// Плашка закрепления: текст ядра, без него — те же слова, что у ядра: «Закреплено: <первая
    /// строка, до 50 знаков с «…»>», без текста — «Сообщение закреплено», снятие — «Закрепление
    /// снято». Автора в тексте нет.
    public static func text(_ pin: PinNotice) -> String {
        if let core = clean(pin.coreText) { return core }
        if pin.isUnpin { return "Закрепление снято" }
        return pinPreview(pin.preview).map { "Закреплено: \($0)" } ?? "Сообщение закреплено"
    }

    /// Длина `pinPreview` в UTF-16, «…» включительно (`PIN_PREVIEW_MAX` ядра).
    public static let pinPreviewMax = 50

    /// Первая непустая строка текста без пробелов по краям, длиннее `pinPreviewMax` — обрезанная
    /// с «…» (не посреди суррогатной пары), как `pinPreview` ядра. `nil` — текста нет.
    public static func pinPreview(_ text: String?) -> String? {
        guard let line = text?
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .lazy
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return nil }
        let units = Array(line.utf16)
        guard units.count > pinPreviewMax else { return line }
        var end = pinPreviewMax - 1
        if UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
        let head = String(decoding: units[0..<end], as: UTF16.self)
        let trimmed = head.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return trimmed + "…"
    }

    /// Текст служебного сообщения (событие или закрепление) или `nil`, если `content` — не
    /// служебное. `currentUserId` — аккаунт, когда событие сохранено без него.
    public static func text(of content: MessageContent, authorId: String, authorName: String, currentUserId: String = "") -> String? {
        if content.service == nil, let pin = content.pin { return text(pin) }
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

    /// Участники через запятую и «и»; аккаунт — «вас», без имени — счётом.
    static func list(_ ids: [String], viewerId viewer: String, name: (String) -> String?) -> String {
        var names: [String] = []
        var unknown = 0
        for id in ids {
            if !viewer.isEmpty, id == viewer {
                names.append("вас")
            } else if let known = name(id) {
                names.append(known)
            } else {
                unknown += 1
            }
        }
        if names.isEmpty { return unknown <= 1 ? "участника" : "\(unknown) \(participants(unknown))" }
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
