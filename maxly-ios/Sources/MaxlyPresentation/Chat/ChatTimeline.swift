import Foundation
import MaxlyDomain

/// Куда экран чата прокручивает ленту по просьбе модели (`ChatViewModel.scrollTarget`).
/// Экран выполняет просьбу один раз и снимает её (`ChatViewModel.consumeScroll`).
public enum ChatScrollTarget: Equatable, Sendable {
    /// Сообщение посередине экрана; `highlight` — коротко подсветить его.
    case message(String, highlight: Bool)
    /// К последнему сообщению живой ленты.
    case bottom
}

/// Окно истории вокруг сообщения далеко за живой лентой: переход к цитате, закрепу или
/// найденному сообщению. Живая лента репозитория держит последние сообщения
/// подряд, и страница из середины истории в неё не ложится — окно живёт в памяти экрана и в
/// кэш не пишется. Листая вниз, окно догружает страницы новее; дойдя до живой ленты, сливается
/// с ней (`joined`): дальше лента снова живая, с историей окна над ней.
struct TimelineWindow: Equatable, Sendable {
    /// Сообщения окна от старых к новым, без повторов.
    private(set) var messages: [Message]
    /// Раньше сообщений нет: страница старше самого старого пришла пустой.
    var reachedOldest = false
    /// Окно дошло до живой ленты и держит её у себя внизу.
    private(set) var joined = false

    init(_ page: [Message]) {
        messages = Self.ordered(page)
    }

    /// Одно сообщение — один ключ: у своего отправленного локальный id другой, серверный тот же.
    static func key(_ message: Message) -> String {
        message.serverId ?? message.id
    }

    /// Страница старше окна: ложатся сообщения не позже самого старого, которых ещё нет.
    /// Возвращает, сколько легло.
    @discardableResult
    mutating func prepend(_ page: [Message]) -> Int {
        guard let oldest = messages.first?.timestamp else {
            messages = Self.ordered(page)
            return messages.count
        }
        let known = Set(messages.map(Self.key))
        let older = Self.ordered(page.filter { $0.timestamp <= oldest && !known.contains(Self.key($0)) })
        messages = older + messages
        return older.count
    }

    /// Страница новее окна: ложатся сообщения не раньше самого нового, которых ещё нет.
    @discardableResult
    mutating func append(_ page: [Message]) -> Int {
        guard let newest = messages.last?.timestamp else {
            messages = Self.ordered(page)
            return messages.count
        }
        let known = Set(messages.map(Self.key))
        let newer = Self.ordered(page.filter { $0.timestamp >= newest && !known.contains(Self.key($0)) })
        messages += newer
        return newer.count
    }

    /// Окно сошлось с живой лентой: у них есть общее сообщение или самое новое в окне не раньше
    /// самого старого живого. Пустая живая лента не сходится ни с чем.
    func meets(_ live: [Message]) -> Bool {
        guard let liveOldest = Self.oldestSent(live) else { return false }
        if let newest = messages.last?.timestamp, newest >= liveOldest { return true }
        let liveKeys = Set(live.map(Self.key))
        return messages.contains { liveKeys.contains(Self.key($0)) }
    }

    /// Слиться с живой лентой: дальше окно держит её у себя внизу (`absorb`).
    mutating func join(_ live: [Message]) {
        joined = true
        absorb(live)
    }

    /// Свежая живая лента: история окна раньше её самого старого сообщения, затем она целиком.
    /// Окно накапливает ушедшее из живой ленты сверху (лента держит последние N), поэтому между
    /// историей окна и живой лентой не остаётся дыры. Удалённое в пределах живой ленты пропадает
    /// и из окна. Пустая живая лента окно не трогает.
    mutating func absorb(_ live: [Message]) {
        guard let liveOldest = Self.oldestSent(live) ?? live.first?.timestamp else { return }
        let liveKeys = Set(live.map(Self.key))
        messages = messages.filter { $0.timestamp < liveOldest && !liveKeys.contains(Self.key($0)) } + live
    }

    /// Самое старое отправленное: свои неотправленные стоят в конце живой ленты со временем «сейчас».
    private static func oldestSent(_ live: [Message]) -> Date? {
        live.first { $0.status == .sent }?.timestamp
    }

    private static func ordered(_ page: [Message]) -> [Message] {
        var seen = Set<String>()
        return page
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert(key($0)).inserted }
    }
}
