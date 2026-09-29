import Foundation

/// Категории ошибок, которые видит UI. Репозиторий переводит в них MaxError ядра.
// TODO: architecture.md, раздел «Ошибки и офлайн».
public enum OrbitlError: Error, Sendable, Equatable {
    case offline
    case sessionExpired
    case server(code: String)
    case invalidRequest
    case unknown
}
