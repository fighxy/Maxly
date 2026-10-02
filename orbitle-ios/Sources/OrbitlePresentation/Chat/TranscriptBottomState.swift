import Foundation

/// «Лента внизу», число новых на кнопке «вниз» и прыжок к последнему сообщению.
///
/// Кнопка «вниз» раньше иногда не срабатывала. Лента ленивая: строки ниже экрана ещё не
/// измерены, и анимированный `scrollTo` к низу считал путь по прикидке высот. Пока лента
/// ехала, строки измерялись, низ отодвигался, и прокрутка вставала выше последнего
/// сообщения. Признак «внизу» не включался, и кнопка оставалась на месте, будто касание
/// не дошло. На iOS 17 метка низа на время пути уходила за экран, и признак тут же
/// сбрасывался обратно.
///
/// Теперь касание сразу ставит «внизу» (кнопка уходит, лента держится низом при росте
/// содержимого) и заводит прыжок. Пока прыжок в пути, уход метки низа признак не
/// сбрасывает. После анимации лента без анимации доводится до низа уже измеренных строк.
/// Если пользователь взял ленту пальцем, прыжок отменяется и доводки нет.
public struct TranscriptBottomState: Equatable, Sendable {
    /// Ближе этого к низу — лента внизу.
    public static let reachDistance: Double = 24
    /// Дальше этого пальцем — лента ушла от низа. Между порогами признак не меняется,
    /// чтобы кнопка не мигала у самого низа.
    public static let leaveDistance: Double = 64

    public private(set) var atBottom = true
    /// Чужие сообщения, пришедшие, пока лента прокручена вверх.
    public private(set) var unseen = 0
    /// Прыжок кнопкой «вниз», который ещё в пути.
    public private(set) var jump: Int?
    private var jumps = 0

    public init() {}

    /// Кнопка видна, когда есть сообщения и лента не внизу.
    public func showsButton(hasMessages: Bool) -> Bool {
        hasMessages && !atBottom
    }

    /// iOS 18: лента сдвинулась. `distance` — сколько до низа содержимого, `dragging` —
    /// двигает палец (или инерция после него). Рост содержимого без пальца признак не
    /// сбрасывает: новое сообщение или картинка не должны показывать кнопку. Во время
    /// прыжка не сбрасывает и инерция: касание кнопки посреди разгона ленты отменяется
    /// только пальцем (`userTookOver`).
    public mutating func scrolled(distance: Double, dragging: Bool) {
        if distance <= Self.reachDistance {
            reachBottom()
        } else if dragging, jump == nil, distance > Self.leaveDistance {
            atBottom = false
        }
    }

    /// Где метка низа ленты. `bottomY` — её низ в координатах экрана ленты (`.infinity`,
    /// если метка не создана: ленивая лента далеко вверху).
    ///
    /// Метка не зависит от того, как прокрутка считает отступы под поле ввода и
    /// клавиатуру: на iOS 18 расстояние до низа из `onScrollGeometryChange` у самого низа
    /// могло не опускаться до порога, и кнопка «вниз» оставалась над последним пузырём.
    /// `dragging` — двигает ли ленту палец: на iOS 18 уходит от низа только он (`nil` —
    /// как на iOS 17, любое движение метки).
    public mutating func markerMoved(bottomY: Double, viewportHeight: Double, dragging: Bool? = nil) {
        let slack = atBottom ? Self.leaveDistance : Self.reachDistance
        let visible = bottomY.isFinite && bottomY >= 0 && bottomY <= viewportHeight + slack
        if visible {
            reachBottom()
        } else if jump == nil, dragging ?? true {
            atBottom = false
        }
    }

    /// Палец взял ленту: прыжок больше не доводится.
    public mutating func userTookOver() {
        jump = nil
    }

    /// Касание кнопки «вниз». Возвращает id прыжка для `finishJump`.
    public mutating func beginJump() -> Int {
        jumps += 1
        jump = jumps
        reachBottom()
        return jumps
    }

    /// Анимация прыжка закончилась. `true` — прыжок всё ещё этот и ленту надо довести до низа.
    public mutating func finishJump(_ id: Int) -> Bool {
        guard jump == id else { return false }
        jump = nil
        return true
    }

    /// Пришли чужие сообщения, а лента не внизу: число на кнопке растёт.
    public mutating func received(_ count: Int) {
        guard count > 0, !atBottom else { return }
        unseen += count
    }

    private mutating func reachBottom() {
        atBottom = true
        unseen = 0
    }
}
