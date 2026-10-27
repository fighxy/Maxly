import Foundation

/// Положение ленты чата: одно место, где решается, куда ей встать и держаться ли низа.
///
/// Раньше это решали три владельца: команда прокрутки (`TranscriptScrollController`), низ ленты
/// (`TranscriptBottomState`) и сам вид ленты флагами открытия, пальца и выбранной цели. Теперь
/// вид передаёт сюда события — открытие, изменение ленты, команду модели, кнопку «вниз», палец,
/// замер низа, выполненную команду — и берёт отсюда выход: команду `request`, цель `reveal(_:)`
/// и `stickToBottom(isJumped:)`. Исполняет их лента (`FeedCollectionController`), модель чата
/// выдаёт только намерения (`ChatScrollTarget`).
public struct TranscriptPosition: Equatable, Sendable {
    /// Куда встать: строка `id` в доле `anchor` видимой области, `latest` — к последнему сообщению.
    public struct Target: Equatable, Sendable {
        public var id: String
        public var anchor: Double
        public var latest: Bool

        public init(id: String, anchor: Double, latest: Bool) {
            self.id = id
            self.anchor = anchor
            self.latest = latest
        }
    }

    /// Что о ленте знает модель чата.
    public struct Feed: Equatable, Sendable {
        public var lastRowId: String?
        /// Первое непрочитанное: чат открывается на нём.
        public var unreadAnchorId: String?
        /// Где читатель остался в прошлый раз.
        public var restoredPlace: String?
        /// Окно перехода к сообщению ещё не пришло: открываться рано.
        public var hasPendingOpen: Bool
        public var isJumped: Bool

        public init(lastRowId: String?, unreadAnchorId: String? = nil, restoredPlace: String? = nil,
                    hasPendingOpen: Bool = false, isJumped: Bool = false) {
            self.lastRowId = lastRowId
            self.unreadAnchorId = unreadAnchorId
            self.restoredPlace = restoredPlace
            self.hasPendingOpen = hasPendingOpen
            self.isJumped = isJumped
        }
    }

    /// Видимая строка и её доля в видимой области: её держит страница истории.
    public struct Place: Equatable, Sendable {
        public var id: String
        public var anchor: Double

        public init(id: String, anchor: Double) {
            self.id = id
            self.anchor = anchor
        }
    }

    /// Что вышло из попытки открыть ленту.
    public enum Opening: Equatable, Sendable {
        /// Цель уже выбрана, строк нет или лента не открывается.
        case none
        /// Ждём окно перехода: модель должна начать его (`startPendingOpen`).
        case waitForWindow
        case unread(String)
        case restored(String)
        case latest
    }

    /// Доля видимой области, в которой встаёт первое непрочитанное.
    public static let unreadAnchor = 0.12

    public private(set) var bottom = TranscriptBottomState()
    public private(set) var scroll = TranscriptScrollController()
    /// Лента ещё встаёт на цель открытия: прочтение не отмечается, кнопок перехода нет.
    public private(set) var isOpening = true
    /// Цель открытия выбирается один раз за показ: поздний ответ сервера не заменяет цель из кэша.
    public private(set) var openingTargetChosen = false
    public private(set) var userScrolling = false

    public init() {}

    public var request: TranscriptScrollController.Request? { scroll.request }

    /// Лента стоит: не открывается и не выполняет команду. Только тогда отмечается прочтение и низ.
    public var isSettled: Bool { !isOpening && scroll.request == nil }

    // MARK: Выход

    /// Прилипать к последнему сообщению. Палец, открытие и окно перехода это отменяют.
    public func stickToBottom(isJumped: Bool) -> Bool {
        if userScrolling || isOpening || isJumped { return false }
        if let request = scroll.request { return request.latest }
        return bottom.followsLatest
    }

    /// Куда встать в этом кадре. Команда прокрутки важнее, иначе — цель открытия.
    public func reveal(_ feed: Feed) -> Target? {
        if let request = scroll.request {
            return Target(id: request.id, anchor: request.anchor, latest: request.latest)
        }
        guard isOpening, !openingTargetChosen, !feed.hasPendingOpen else { return nil }
        return Self.openingTarget(feed)
    }

    private static func openingTarget(_ feed: Feed) -> Target? {
        guard let last = feed.lastRowId else { return nil }
        if let id = feed.unreadAnchorId { return Target(id: id, anchor: unreadAnchor, latest: false) }
        if let id = feed.restoredPlace { return Target(id: id, anchor: 0, latest: false) }
        return Target(id: last, anchor: 1, latest: true)
    }

    // MARK: События

    /// Открытие: непрочитанное, сохранённое место или низ.
    public mutating func open(_ feed: Feed) -> Opening {
        guard !openingTargetChosen, feed.lastRowId != nil else { return .none }
        if feed.hasPendingOpen { return .waitForWindow }
        openingTargetChosen = true
        guard let target = Self.openingTarget(feed) else { return .none }
        if target.latest {
            requestLatest(target.id)
            return .latest
        }
        requestHistory(target.id, anchor: target.anchor)
        return feed.unreadAnchorId == target.id ? .unread(target.id) : .restored(target.id)
    }

    /// Лента ушла с экрана: при следующем показе она открывается заново.
    public mutating func disappeared() {
        scroll.cancel()
        openingTargetChosen = false
        isOpening = true
    }

    /// Лента изменилась. Пока она открывается, это ещё одна попытка открыть её.
    ///
    /// `appendedOutgoing(count)` — есть ли среди `count` последних сообщений своё.
    public mutating func feedChanged(
        _ change: CollectionChange,
        fromPaging: Bool,
        place: Place?,
        feed: Feed,
        appendedOutgoing: (Int) -> Bool
    ) -> Opening {
        guard let last = feed.lastRowId else { return .none }
        if isOpening { return open(feed) }
        switch change {
        case .prepended, .trimmed, .reload:
            // Снимок коллекции сам держит видимую строку. Вторая команда прокрутки её сдвигает.
            return .none
        default:
            break
        }
        if fromPaging {
            if !userScrolling, scroll.request == nil, let place {
                if bottom.followsLatest && !feed.isJumped { requestLatest(last) }
                else { requestHistory(place.id, anchor: place.anchor) }
            }
            return .none
        }
        guard !feed.isJumped else { return .none }
        if case .appended(let count) = change, count > 0,
           bottom.followsLatest || appendedOutgoing(count) {
            requestLatest(last)
        }
        return .none
    }

    /// Команда модели: переход к сообщению или вниз.
    public mutating func perform(_ target: ChatScrollTarget, lastRowId: String?) {
        openingTargetChosen = true
        switch target {
        case .message(let id, _): requestHistory(id, anchor: 0.5)
        case .bottom: if let lastRowId { requestLatest(lastRowId) }
        }
    }

    /// Кнопка «вниз», когда возвращаться из перехода некуда.
    public mutating func goDown(lastRowId: String?) {
        guard let lastRowId else { return }
        requestLatest(lastRowId)
    }

    /// Палец на ленте. `takeover` — он перехватил ленту: команда и цель открытия отменяются.
    public mutating func userScroll(moving: Bool, takeover: Bool) {
        userScrolling = moving
        guard takeover else { return }
        scroll.cancel()
        bottom.userTookOver()
        openingTargetChosen = true
        isOpening = false
    }

    /// Лента выполнила команду `token`. `false` — команда уже заменена или отменена.
    @discardableResult
    public mutating func scrollFinished(_ token: Int, confirmed: Bool) -> Bool {
        guard scroll.finish(token) else { return false }
        isOpening = false
        if !confirmed { bottom.beginReadingHistory() }
        return true
    }

    /// Замер последней строки (см. `TranscriptBottomState.measuredLastRow`).
    public mutating func measuredLastRow(minY: Double?, maxY: Double?, viewportMin: Double, viewportMax: Double,
                                         contentFits: Bool, buttonMin: Double?) {
        bottom.measuredLastRow(minY: minY, maxY: maxY, viewportMin: viewportMin, viewportMax: viewportMax,
                               userScrolling: userScrolling, contentFits: contentFits, buttonMin: buttonMin)
    }

    /// Поле ввода или клавиатура сдвинули низ ленты: лента, что держит низ, встаёт к нему снова.
    public mutating func chromeMoved(lastRowId: String?) {
        guard scroll.request == nil else { return }
        viewportResized(lastRowId: lastRowId)
    }

    /// Высота самой ленты поменялась. Держит низ и поверх команды: та встала бы по старой высоте.
    public mutating func viewportResized(lastRowId: String?) {
        guard bottom.followsLatest, !userScrolling, !isOpening, let lastRowId else { return }
        requestLatest(lastRowId)
    }

    /// Строки поменяли высоту (картинка догрузилась, реакция): низ уехал — лента встаёт к нему.
    public mutating func rowsResized(lastRowId: String?) {
        guard !bottom.atBottom else { return }
        chromeMoved(lastRowId: lastRowId)
    }

    // MARK: Команды

    private mutating func requestLatest(_ id: String) {
        bottom.beginFollowing()
        scroll.start(id: id, anchor: 1, latest: true)
    }

    private mutating func requestHistory(_ id: String, anchor: Double) {
        bottom.beginReadingHistory()
        scroll.start(id: id, anchor: anchor, latest: false)
    }
}
