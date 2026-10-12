import Foundation
import MaxlyDomain

/// Когда искать звонок, который звонит, но не пришёл пушем (`docs/background.md`).
///
/// Пуш о звонке (137) приходит только живому соединению. Если приложение было выгружено, а о
/// звонке сообщила веб-версия, при открытии звонок ещё идёт, но пуш уже прошёл. Поэтому после
/// запуска и после каждого возврата из фона приложение один раз смотрит `calls` ответа на вход
/// и спрашивает сервер (`GET_INBOUND_CALLS` 103). Тело запроса 103 неизвестно (MAX Android его
/// не шлёт): если сервер ответит ошибкой или оборвёт соединение сразу после запроса, опрос 103
/// выключается навсегда, а `calls` входа смотрятся по-прежнему.
public struct RingingProbePolicy: Sendable, Equatable {
    /// Сколько ждать обрыва после запроса: обрыв в это окно считается ответом на 103.
    public static let dropWindow: Duration = .seconds(5)

    /// Поиск положен: был запуск или возврат из фона, а искать ещё не успели.
    public private(set) var isPending = true
    /// Сервер не понял опрос 103: больше его не шлём.
    public private(set) var isDisabled: Bool

    public init(disabled: Bool) {
        isDisabled = disabled
    }

    /// Что делать после поиска.
    public enum Verdict: Equatable, Sendable {
        /// Готово; следующий поиск — после возврата из фона.
        case done
        /// Опрос 103 не ушёл (нет связи, отменён): искать при следующем подключении.
        case retry
        /// Сервер не понял опрос 103: выключить его навсегда. `reason` — для журнала.
        case disable(reason: String)
    }

    /// Приложение ушло в фон: после возврата искать снова.
    public mutating func wentToBackground() {
        isPending = true
    }

    /// Можно ли искать сейчас.
    public func shouldCheck(foreground: Bool, online: Bool, signedIn: Bool) -> Bool {
        isPending && foreground && online && signedIn
    }

    /// Слать ли опрос 103 вместе с поиском.
    public var sendsProbe: Bool { !isDisabled }

    /// Поиск начался.
    public mutating func started() {
        isPending = false
    }

    /// Поиск закончился. `probeError` — ошибка опроса 103, если он был; `droppedSoon` —
    /// соединение оборвалось в `dropWindow` после запроса.
    public mutating func finished(probed: Bool, probeError: MaxlyError?, droppedSoon: Bool) -> Verdict {
        let verdict = probed ? Self.verdict(probeError, droppedSoon: droppedSoon) : .done
        switch verdict {
        case .done: break
        case .retry: isPending = true
        case .disable: isDisabled = true
        }
        return verdict
    }

    private static func verdict(_ error: MaxlyError?, droppedSoon: Bool) -> Verdict {
        if droppedSoon { return .disable(reason: "drop") }
        switch error {
        case nil:
            return .done
        case .networkUnavailable?, .cancelled?, .authExpired?:
            return .retry
        // Пауза сервера после too.many.requests — не ответ на сам опрос.
        case .server(let code, _)? where code == MaxlyError.rateLimitCode:
            return .retry
        case .server(let code, _)?:
            return .disable(reason: "server:\(code)")
        case let error?:
            return .disable(reason: "\(error)")
        }
    }
}
