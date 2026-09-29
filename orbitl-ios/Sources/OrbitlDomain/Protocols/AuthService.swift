import Foundation

/// Вход, восстановление и завершение сессии.
// TODO: architecture.md, раздел «Аутентификация и сессии».
public protocol AuthService: Sendable {
    var isAuthorized: Bool { get async }
    func restoreSession() async throws(OrbitlError)
    func logout() async
}
