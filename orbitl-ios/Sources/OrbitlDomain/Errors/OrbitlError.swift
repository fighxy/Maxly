import Foundation

/// Категории ошибок, которые видит UI. Слой данных переводит в них ошибки ядра,
/// сервера и базы (architecture.md, «Ошибки и офлайн»).
public enum OrbitlError: Error, Sendable, Equatable {
    /// Нет сети или соединение с сервером потеряно.
    case networkUnavailable
    /// Сессия истекла, нужно войти заново.
    case authExpired
    /// Сервер вернул ошибку.
    case server(code: String)
    /// Запрос отклонён как неверный.
    case invalidRequest
    /// Пользовательский ввод отклонён, например неверный пароль. Текст можно показать как есть.
    case rejected(String)
    /// Не удалось прочитать или записать локальную базу.
    case storageError
    /// Синхронизация с сервером не удалась.
    case syncFailed
    case unknown
}

extension OrbitlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkUnavailable: "Нет соединения с сервером"
        case .authExpired: "Сессия истекла, войдите снова"
        case .server(let code): "Ошибка сервера (\(code))"
        case .invalidRequest: "Сервер отклонил запрос"
        case .rejected(let message): message
        case .storageError: "Не удалось сохранить данные на устройстве"
        case .syncFailed: "Не удалось синхронизироваться с сервером"
        case .unknown: "Что-то пошло не так"
        }
    }
}
