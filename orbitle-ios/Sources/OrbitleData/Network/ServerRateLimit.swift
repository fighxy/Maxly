import Foundation
import OrbitleDomain

/// Пауза после ответа сервера `too.many.requests`.
///
/// Сервер Max отказывает так, когда клиент читает слишком часто (история, комментарии,
/// общие медиа, карточки чатов). Каждый новый запрос в это время только продлевает отказ,
/// поэтому фоновые чтения на паузу на сервер не уходят, а сразу получают тот же отказ.
/// Пауза растёт с каждым отказом подряд (15, 30, 60, 120 с) и сбрасывается удачным чтением.
/// Отправку, отметки прочтения и вход пауза не трогает: их решает вызывающий (`MaxIosCore`).
public actor ServerRateLimit {
    public static let shared = ServerRateLimit()
    /// Ключ ошибки сервера, по которому включается пауза.
    public static let key = OrbitleError.rateLimitCode
    static let pauses: [TimeInterval] = [15, 30, 60, 120]

    private let clock: @Sendable () -> Date
    private var until = Date.distantPast
    private var strikes = 0

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    /// Сколько секунд ещё ждать. `nil` — можно спрашивать сервер.
    public func remaining() -> TimeInterval? {
        let left = until.timeIntervalSince(clock())
        return left > 0 ? left : nil
    }

    /// Сервер ответил `too.many.requests`.
    public func noteLimited() {
        let pause = Self.pauses[min(strikes, Self.pauses.count - 1)]
        strikes += 1
        until = max(until, clock().addingTimeInterval(pause))
    }

    /// Чтение прошло: следующий отказ снова начнёт с короткой паузы.
    public func noteSuccess() {
        strikes = 0
    }

    public static func isLimit(_ key: String?) -> Bool {
        key == Self.key
    }
}
