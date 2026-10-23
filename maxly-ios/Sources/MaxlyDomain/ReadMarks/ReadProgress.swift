import Foundation

/// Что прочитано за один показ экрана чата и до какого сообщения отметить чат прочитанным
/// (docs/read-marks.md). Чистое значение: экран сообщает увиденное, модель чата спрашивает
/// кандидата, когда отправлять — решает `ReadMarkScheduler`.
///
/// - `floor` — до какого времени чат уже прочитан при открытии: своя позиция
///   (`OwnReadMark`), а если непрочитанных не было — последнее сообщение или сообщение перед
///   разделителем. Отметка не новее порога не уходит: открыть прочитанный чат и листать старую
///   историю (в том числе окно перехода) ничего не отправляет. Порог одинаков при обычных и
///   скрытых отметках о прочтении: при скрытых его поднимает местная отметка ядра.
/// - `seen` — самое новое увиденное время за этот показ. Не у низа читается только увиденное.
/// - `following` — лента у низа живой ленты: читается последнее сообщение, и новое тоже.
///
/// Кандидат — самое новое чужое сообщение, принятое сервером: своё сообщение чат и так не
/// делает непрочитанным, отметка ради него не нужна.
public struct ReadProgress: Sendable, Hashable {
    public private(set) var seen: Int64 = 0
    public private(set) var following = false
    /// Своя позиция чата при открытии.
    private var position: Int64 = 0
    /// До какого времени чат прочитан по ленте при открытии: последнее сообщение или сообщение
    /// перед разделителем. `nil` — ещё неизвестно.
    private var openedReadTime: Int64?

    public init() {}

    public var floor: Int64 { max(position, openedReadTime ?? 0) }

    /// Новое открытие чата: прочитано до своей позиции, увиденного ещё нет.
    public mutating func open(position: Int64) {
        self.position = max(0, position)
        openedReadTime = nil
        seen = 0
        following = false
    }

    /// По ленте при открытии всё до `time` уже прочитано: непрочитанных не было (последнее
    /// сообщение) или они ниже (сообщение перед разделителем). Разделитель, вставший позже,
    /// опускает это место.
    public mutating func noteReadAtOpen(_ time: Int64) {
        openedReadTime = max(0, time)
    }

    /// Что видно: время самого нового увиденного сообщения (`nil` — ничего) и стоит ли лента
    /// у низа живой ленты.
    public mutating func see(_ time: Int64?, following: Bool) {
        self.following = following
        if let time { seen = max(seen, time) }
    }

    /// Экран ушёл: увиденное этого показа забыто, следующий показ сообщит своё. Порог остаётся
    /// до нового открытия.
    public mutating func endShowing() {
        seen = 0
        following = false
    }

    /// До какого сообщения читать. `shown` — лента на экране (живая или окно перехода), `live` —
    /// живая лента; обе от старых к новым. `nil` — читать нечего.
    public func candidate(shown: [Message], live: [Message], isOutgoing: (Message) -> Bool) -> ReadMark? {
        for message in (following ? live : shown).reversed() where !isOutgoing(message) {
            guard let mark = ReadMark(message: message) else { continue }
            guard following || mark.time <= seen else { continue }
            // Самое новое подходящее не новее порога — остальные тем более.
            return mark.time > floor ? mark : nil
        }
        return nil
    }
}
