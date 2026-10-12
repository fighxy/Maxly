import Foundation
import MaxlyDomain

/// Когда спрашивать сервер, кто звонит прямо сейчас (`GET_INBOUND_CALLS` 103, эксперимент;
/// `docs/background.md`).
///
/// Пуш о звонке (137) приходит только живому соединению. Если приложение было выгружено, а о
/// звонке сообщила веб-версия, при открытии приложения звонок ещё идёт, но пуш уже прошёл.
/// Поэтому после запуска и после каждого возврата из фона приложение один раз спрашивает
/// сервер. Ответа на 103 нет ни в одном референсе: если сервер ответит ошибкой или оборвёт
/// соединение сразу после запроса, опрос выключается навсегда.
public struct RingingProbePolicy: Sendable, Equatable {
    /// Сколько ждать обрыва после запроса: обрыв в это окно считается ответом на 103.
    public static let dropWindow: Duration = .seconds(5)

    /// Опрос положен: был запуск или возврат из фона, а спросить ещё не успели.
    public private(set) var isPending = true
    /// Сервер не понял опрос: больше не спрашиваем.
    public private(set) var isDisabled: Bool

    public init(disabled: Bool) {
        isDisabled = disabled
    }

    /// Что делать с опросом после ответа.
    public enum Verdict: Equatable, Sendable {
        /// Ответ разобран; следующий опрос — после возврата из фона.
        case done
        /// Запрос не ушёл (нет связи, отменён): спросить при следующем подключении.
        case retry
        /// Сервер не понял опрос: выключить навсегда. `reason` — для журнала.
        case disable(reason: String)
    }

    /// Приложение ушло в фон: после возврата спросить снова.
    public mutating func wentToBackground() {
        isPending = true
    }

    /// Можно ли спросить сейчас.
    public func shouldProbe(foreground: Bool, online: Bool, signedIn: Bool) -> Bool {
        !isDisabled && isPending && foreground && online && signedIn
    }

    /// Запрос ушёл.
    public mutating func started() {
        isPending = false
    }

    /// Ответ пришёл. `droppedSoon` — соединение оборвалось в `dropWindow` после запроса.
    public mutating func finished(_ result: CallCenter.RingingCheck, droppedSoon: Bool) -> Verdict {
        let verdict = Self.verdict(result, droppedSoon: droppedSoon)
        switch verdict {
        case .done: break
        case .retry: isPending = true
        case .disable: isDisabled = true
        }
        return verdict
    }

    private static func verdict(_ result: CallCenter.RingingCheck, droppedSoon: Bool) -> Verdict {
        if droppedSoon { return .disable(reason: "drop") }
        switch result {
        case .shown, .nobody:
            return .done
        case .failed(.networkUnavailable), .failed(.cancelled), .failed(.authExpired):
            return .retry
        // Пауза сервера после too.many.requests — не ответ на сам опрос.
        case .failed(.server(let code, _)) where code == MaxlyError.rateLimitCode:
            return .retry
        case .failed(.server(let code, _)):
            return .disable(reason: "server:\(code)")
        case .failed(let error):
            return .disable(reason: "\(error)")
        }
    }
}
