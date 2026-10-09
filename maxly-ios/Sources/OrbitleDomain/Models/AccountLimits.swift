import Foundation

/// Ограничения аккаунта после входа на этом устройстве.
///
/// Сервер Max временно ограничивает новый сеанс (облачный пароль, завершение других сеансов),
/// а новому аккаунту может ограничить сообщения и группы. Признака в ответе нет: клиент знает
/// только, как вошли и когда. Срок взят из клиента Komet: ограничения входа снимаются примерно
/// через сутки. У регистрации срока нет, сервер снимает их сам.
public struct AccountLimits: Hashable, Sendable {
    public enum Entry: String, Hashable, Sendable {
        case login
        case registration
    }

    public static let loginLimitsDuration: TimeInterval = 24 * 60 * 60

    public var entry: Entry
    public var grantedAt: Date
    /// Панель после входа уже показана.
    public var isShown: Bool

    public init(entry: Entry, grantedAt: Date, isShown: Bool = false) {
        self.entry = entry
        self.grantedAt = grantedAt
        self.isShown = isShown
    }

    /// Когда ограничения входа примерно снимутся. У регистрации срока нет.
    public var liftsAt: Date? {
        entry == .login ? grantedAt.addingTimeInterval(Self.loginLimitsDuration) : nil
    }

    /// Ограничения входа ещё действуют: строка в настройках видна.
    public func isActive(now: Date) -> Bool {
        guard let liftsAt else { return false }
        return now < liftsAt
    }

    /// Показать панель на главном экране: ещё не показана и не устарела.
    public func needsNotice(now: Date) -> Bool {
        !isShown && (entry == .registration || isActive(now: now))
    }
}

/// Где лежит отметка о новом сеансе.
@MainActor
public protocol AccountLimitsStore: AnyObject {
    func load() -> AccountLimits?
    func save(_ limits: AccountLimits?)
}

/// Отметка только в памяти: для тестов и превью.
@MainActor
public final class InMemoryAccountLimitsStore: AccountLimitsStore {
    public private(set) var saved: AccountLimits?

    public init(_ limits: AccountLimits? = nil) {
        saved = limits
    }

    public func load() -> AccountLimits? { saved }

    public func save(_ limits: AccountLimits?) {
        saved = limits
    }
}

extension AuthPhase {
    /// Как начнётся сеанс, если следующий шаг — успешный вход: после кода или пароля это вход,
    /// после имени — регистрация. `nil` — восстановление сохранённого сеанса, а не новый сеанс.
    public var freshEntry: AccountLimits.Entry? {
        switch self {
        case .codeSent, .password: .login
        case .registration: .registration
        case .restoring, .signedOut, .signedIn, .expired: nil
        }
    }
}
