import Foundation

/// Шаг входа. Экран читает его из потока, а не из исключения.
public enum AuthPhase: Sendable, Equatable {
    case restoring
    case signedOut
    case codeSent(codeLength: Int?)
    case password(hint: String?)
    case registration
    case signedIn(userId: String)
    /// Сервер отклонил токен или заблокировал аккаунт. Локальная база уже стёрта, нужен вход.
    case expired
}

/// Вход, восстановление и завершение сессии.
///
/// Токен логина хранит ядро (Keychain). Этот сервис только переводит шаги
/// входа и просит репозитории обновить кэш.
///
/// Ошибки шагов входа приходят уже с русским текстом для экрана (`MaxlyError.rejected`).
/// Ответ на запрос из отменённой попытки (`cancelLogin`, выход) не меняет шаг,
/// а метод бросает `MaxlyError.cancelled`.
public protocol AuthService: Sendable {
    func phases() -> AsyncStream<AuthPhase>
    var isAuthorized: Bool { get async }
    func restoreSession() async
    func requestCode(phone: String) async throws(MaxlyError)
    func resendCode() async throws(MaxlyError)
    func verifyCode(_ code: String) async throws(MaxlyError)
    func submitPassword(_ password: String) async throws(MaxlyError)
    func register(firstName: String, lastName: String) async throws(MaxlyError)
    /// Вернуться к вводу номера: забыть код, пароль и регистрацию текущей попытки.
    /// После входа ничего не делает.
    func cancelLogin() async
    func logout() async
    /// Плашка ограничения входа или пояснение на экране входа. `nil` — показывать нечего.
    func loginNotices() -> AsyncStream<LoginNotice?>
    /// Снова подключить ядро тем же токеном, не уходя со списка чатов.
    func retryHeldLogin() async
}

/// Пояснение, почему вход ограничен. Текст уже готов для экрана.
public struct LoginNotice: Sendable, Equatable {
    public enum Place: Sendable, Equatable {
        /// Над полем номера, после сброса сессии.
        case loginForm
        /// Над списком чатов, пока токен ещё жив.
        case chatList
    }

    public var title: String
    public var message: String?
    public var place: Place

    public init(title: String, message: String?, place: Place) {
        self.title = title
        self.message = message
        self.place = place
    }

    /// Заголовок сервера важнее нашего. Текст сервера берём, только если заголовок пришёл:
    /// иначе на экране наши запасные строки, а не обрывок ответа.
    public static func composed(
        serverTitle: String?,
        localizedMessage: String?,
        detail: String?,
        fallbackTitle: String,
        fallbackBody: String
    ) -> (title: String, message: String?) {
        let title = nonempty(serverTitle)
        if let title {
            return (title, nonempty(localizedMessage) ?? nonempty(detail))
        }
        return (fallbackTitle, fallbackBody)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public extension AuthService {
    func loginNotices() -> AsyncStream<LoginNotice?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }

    func retryHeldLogin() async {}
}
