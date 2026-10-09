import Foundation
import Observation
import MaxlyDomain

/// Что рисует экран ограничений: заголовок, пояснение и список ограничений.
public struct AccountLimitsContent: Hashable, Sendable {
    /// Значок пункта: экран сам выбирает символ.
    public enum Icon: Hashable, Sendable {
        case password, sessions, messages, groups, other
    }

    public struct Item: Hashable, Sendable {
        public let icon: Icon
        public let title: String
        public let detail: String
    }

    public let entry: AccountLimits.Entry
    public let title: String
    public let message: String
    public let items: [Item]
}

/// Строка «Аккаунт временно ограничен» в настройках, пока ограничения входа действуют.
public struct AccountLimitsRow: Hashable, Sendable {
    public let title: String
    public let subtitle: String
}

/// Тексты экрана ограничений. Часы и календарь передаются снаружи, чтобы тесты не зависели от запуска.
public struct AccountLimitsText: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = ChatListFormatter.defaultCalendar()) {
        self.calendar = calendar
    }

    public func content(_ limits: AccountLimits, now: Date) -> AccountLimitsContent {
        switch limits.entry {
        case .login:
            AccountLimitsContent(
                entry: .login,
                title: Self.loginTitle,
                message: "Вы вошли в Max на этом устройстве. Пока сеанс новый, сервер ограничивает часть настроек безопасности. "
                    + liftsSentence(limits, now: now),
                items: [
                    .init(icon: .password, title: "Пароль для входа", detail: "Нельзя включить, сменить или отключить пароль."),
                    .init(
                        icon: .sessions,
                        title: "Другие сеансы",
                        detail: "Нельзя завершить сеансы на других устройствах. Это можно сделать с устройства, где вход выполнен давно."
                    ),
                ]
            )
        case .registration:
            AccountLimitsContent(
                entry: .registration,
                title: "Аккаунт может быть ограничен",
                message: "Новым аккаунтам сервер иногда ограничивает часть действий. Ограничения выдают не всем, и сервер снимает их сам.",
                items: [
                    .init(icon: .messages, title: "Сообщения", detail: "Возможно, писать получится только тем, у кого вы уже есть в контактах."),
                    .init(icon: .groups, title: "Группы", detail: "Вступить в группу может не получиться."),
                    .init(
                        icon: .other,
                        title: "Другие действия",
                        detail: "Полного списка сервер не сообщает. Если действие не сработало, попробуйте позже."
                    ),
                ]
            )
        }
    }

    /// Строка в настройках. `nil`, если ограничений входа нет или срок уже вышел.
    public func row(_ limits: AccountLimits?, now: Date) -> AccountLimitsRow? {
        guard let limits, limits.isActive(now: now), let liftsAt = limits.liftsAt else { return nil }
        return AccountLimitsRow(title: Self.loginTitle, subtitle: "Снимутся примерно \(moment(liftsAt, now: now))")
    }

    /// «сегодня в 14:30», «завтра в 09:05», иначе «5 октября в 14:30».
    public func moment(_ date: Date, now: Date) -> String {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "сегодня в \(time)"
        case 1: return "завтра в \(time)"
        default:
            let month = Self.monthsGenitive[((parts.month ?? 1) - 1) % 12]
            return "\(parts.day ?? 1) \(month) в \(time)"
        }
    }

    private func liftsSentence(_ limits: AccountLimits, now: Date) -> String {
        guard let liftsAt = limits.liftsAt else { return "" }
        return now < liftsAt ? "Ограничения снимутся примерно \(moment(liftsAt, now: now))." : "Ограничения уже должны были сняться."
    }

    private static let loginTitle = "Аккаунт временно ограничен"
    private static let monthsGenitive = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    ]
}

/// Отметка о новом сеансе для экранов: панель на главном экране и строка в настройках.
///
/// Выход стирает отметку: она про прежний сеанс. Новый вход заменяет её целиком.
@MainActor
@Observable
public final class AccountLimitsSettings {
    public private(set) var limits: AccountLimits?

    @ObservationIgnored private let store: any AccountLimitsStore
    @ObservationIgnored private let clock: () -> Date

    public init(store: any AccountLimitsStore, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.clock = clock
        limits = store.load()
    }

    /// Вход по коду, паролю или регистрация: новая отметка, панель ещё не показана.
    public func grant(_ entry: AccountLimits.Entry) {
        save(AccountLimits(entry: entry, grantedAt: clock()))
        Log.info(.auth, "Новый сеанс: \(entry.rawValue)")
    }

    /// Панель закрыли: сама она больше не всплывёт. Строка в настройках остаётся, пока срок не вышел.
    public func markShown() {
        guard var current = limits, !current.isShown else { return }
        current.isShown = true
        save(current)
    }

    public func clear() {
        guard limits != nil else { return }
        save(nil)
    }

    /// Ограничения для панели на главном экране, если её пора показать.
    public func pendingNotice(now: Date) -> AccountLimits? {
        guard let limits, limits.needsNotice(now: now) else { return nil }
        return limits
    }

    private func save(_ next: AccountLimits?) {
        limits = next
        store.save(next)
    }
}
