import Foundation

/// Шаг входа. Экран читает его из потока, а не из исключения.
public enum AuthPhase: Sendable, Equatable {
    case restoring
    case signedOut
    case codeSent(codeLength: Int?)
    case password(hint: String?)
    case registration
    case signedIn(userId: String)
    /// Сервер отклонил сохранённый токен. Локальная база при этом не стирается.
    case expired
}

/// Вход, восстановление и завершение сессии.
///
/// Токен логина хранит ядро (Keychain). Этот сервис только переводит шаги
/// входа и просит репозитории обновить кэш.
///
/// Ошибки шагов входа приходят уже с русским текстом для экрана (`OrbitleError.rejected`).
/// Ответ на запрос из отменённой попытки (`cancelLogin`, выход) не меняет шаг,
/// а метод бросает `OrbitleError.cancelled`.
public protocol AuthService: Sendable {
    func phases() -> AsyncStream<AuthPhase>
    var isAuthorized: Bool { get async }
    func restoreSession() async
    func requestCode(phone: String) async throws(OrbitleError)
    func resendCode() async throws(OrbitleError)
    func verifyCode(_ code: String) async throws(OrbitleError)
    func submitPassword(_ password: String) async throws(OrbitleError)
    func register(firstName: String, lastName: String) async throws(OrbitleError)
    /// Вернуться к вводу номера: забыть код, пароль и регистрацию текущей попытки.
    /// После входа ничего не делает.
    func cancelLogin() async
    func logout() async
}
