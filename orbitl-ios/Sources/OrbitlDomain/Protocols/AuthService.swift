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
public protocol AuthService: Sendable {
    func phases() -> AsyncStream<AuthPhase>
    var isAuthorized: Bool { get async }
    func restoreSession() async
    func requestCode(phone: String) async throws(OrbitlError)
    func resendCode() async throws(OrbitlError)
    func verifyCode(_ code: String) async throws(OrbitlError)
    func submitPassword(_ password: String) async throws(OrbitlError)
    func register(firstName: String, lastName: String) async throws(OrbitlError)
    func logout() async
}
