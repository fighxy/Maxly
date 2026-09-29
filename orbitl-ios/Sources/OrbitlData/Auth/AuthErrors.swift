import Foundation
import OrbitlDomain

/// Шаг входа, на котором упал вызов ядра. От него зависит текст ошибки.
enum AuthStep: Sendable {
    case requestCode
    case verifyCode
    case password
    case register
}

/// Ошибки шагов входа с русским текстом для экрана.
///
/// Ядро различает только вид ошибки (`ErrorKind`) и ключ сервера. Неверный код приходит
/// как `SERVER`, неверный пароль как `AUTH`, поэтому один и тот же вид значит разное
/// на разных шагах. Сеть, отмена и сбои без категории идут общим путём (`CoreErrors`).
enum AuthErrors {
    static let tooManyAttempts = "Слишком много попыток. Подождите немного и попробуйте снова"

    static func map(_ error: Error, during step: AuthStep) -> OrbitlError {
        if let error = error as? OrbitlError { return error }
        guard let failure = error as? CoreFailure else { return CoreErrors.orbitl(error) }
        let key = failure.key?.lowercased() ?? ""
        switch failure.kind {
        case "AUTH", "SERVER", "NOT_FOUND":
            if isRateLimit(key) { return .rejected(tooManyAttempts) }
            return .rejected(rejection(during: step, key: key))
        case "SESSION_EXPIRED":
            // Во время входа это не сохранённый токен, а устаревшая попытка входа.
            switch step {
            case .verifyCode: return .rejected("Код устарел. Запросите новый")
            case .requestCode, .password, .register: return .rejected("Попытка входа устарела. Начните заново")
            }
        default:
            return CoreErrors.orbitl(error)
        }
    }

    private static func rejection(during step: AuthStep, key: String) -> String {
        switch step {
        case .requestCode:
            return "Не удалось отправить код. Проверьте номер телефона"
        case .verifyCode:
            if key.contains("expire") { return "Код устарел. Запросите новый" }
            return "Неверный код"
        case .password:
            return "Неверный пароль"
        case .register:
            return "Не удалось создать аккаунт. Проверьте имя и попробуйте снова"
        }
    }

    /// Ключи сервера про лимиты попыток. Точных ключей Max нет в референсах, поэтому по словам.
    static func isRateLimit(_ key: String) -> Bool {
        ["limit", "many", "flood", "attempt", "frequent"].contains { key.contains($0) }
    }
}
