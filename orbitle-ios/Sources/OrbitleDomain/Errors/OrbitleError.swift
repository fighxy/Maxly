import Foundation

/// Категории ошибок, которые видит UI. Слой данных переводит в них ошибки ядра,
/// сервера и базы (architecture.md, «Ошибки и офлайн»).
public enum OrbitleError: Error, Sendable, Equatable {
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
    /// Действие отменено: пользователь ушёл с шага или ответ пришёл на устаревший запрос.
    /// Экран такую ошибку не показывает.
    case cancelled
    case unknown
}

extension OrbitleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkUnavailable: "Нет соединения с сервером"
        case .authExpired: "Сессия истекла, войдите снова"
        case .server(let code) where code == Self.rateLimitCode: "Сервер просит подождать: слишком много запросов"
        case .server(let code): "Ошибка сервера (\(code)). Попробуйте позже"
        case .invalidRequest: "Сервер отклонил запрос"
        case .rejected(let message): message
        case .storageError: "Не удалось сохранить данные на устройстве"
        case .syncFailed: "Не удалось синхронизироваться с сервером"
        case .cancelled: "Действие отменено"
        case .unknown: "Что-то пошло не так"
        }
    }
}

extension OrbitleError {
    /// Текст для экрана. `nil` у отмены: её пользователю не показывают.
    public var userMessage: String? {
        self == .cancelled ? nil : errorDescription
    }

    /// Код ответа сервера, когда клиент спрашивает слишком часто.
    public static let rateLimitCode = "too.many.requests"

    /// Сервер ответил «слишком много запросов»: повтор пройдёт сам после паузы.
    public var isRateLimit: Bool {
        self == .server(code: Self.rateLimitCode)
    }

    /// Повтор того же действия позже может пройти без участия пользователя.
    public var isTransient: Bool {
        switch self {
        case .networkUnavailable, .server, .syncFailed: true
        case .authExpired, .invalidRequest, .rejected, .storageError, .cancelled, .unknown: false
        }
    }
}

extension OrbitleError {
    /// Код устарел, и сервис входа уже выслал новый. Экран стирает поле и заново
    /// запускает таймер повторной отправки.
    public static let codeRenewed = OrbitleError.rejected("Код устарел — выслали новый")
}
