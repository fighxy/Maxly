package app.orbitle.data

import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.CancellationException

/** Перевод ошибок ядра в категории UI. */
object CoreErrors {
    fun map(error: Throwable): OrbitleError {
        if (error is OrbitleError) return error
        if (error is CancellationException) return OrbitleError.Cancelled
        val failure = error as? CoreFailure ?: return OrbitleError.Unknown
        return when (failure.kind) {
            "NETWORK", "TIMEOUT", "CLOSED" -> OrbitleError.NetworkUnavailable
            "SESSION_EXPIRED" -> OrbitleError.AuthExpired
            // Отказ шага входа переводит AuthErrors, а вне входа это отклонённый запрос.
            "AUTH", "NOT_FOUND" -> OrbitleError.InvalidRequest
            "SERVER", "UPLOAD" -> OrbitleError.Server(failure.key ?: failure.kind)
            // Сервер ответил без нужных полей: это его сбой, а не ошибка пользователя.
            "MALFORMED_REPLY" -> OrbitleError.Server(failure.kind)
            "CANCELLED" -> OrbitleError.Cancelled
            else -> OrbitleError.Unknown
        }
    }
}

/** Шаг входа, на котором упал вызов ядра. От него зависит текст ошибки. */
enum class AuthStep { REQUEST_CODE, VERIFY_CODE, PASSWORD, REGISTER }

/**
 * Ошибки шагов входа с русским текстом для экрана. Неверный код приходит как `SERVER`,
 * неверный пароль как `AUTH`, поэтому один и тот же вид значит разное на разных шагах.
 */
object AuthErrors {
    const val TOO_MANY_ATTEMPTS = "Слишком много попыток. Подождите немного и попробуйте снова"

    fun map(error: Throwable, step: AuthStep): OrbitleError {
        if (error is OrbitleError) return error
        val failure = error as? CoreFailure ?: return CoreErrors.map(error)
        val key = failure.key?.lowercase().orEmpty()
        return when (failure.kind) {
            "AUTH", "SERVER", "NOT_FOUND" ->
                if (isRateLimit(key)) OrbitleError.Rejected(TOO_MANY_ATTEMPTS)
                else OrbitleError.Rejected(rejection(step, key))
            "SESSION_EXPIRED" -> when (step) {
                AuthStep.VERIFY_CODE -> OrbitleError.Rejected("Код устарел. Запросите новый")
                else -> OrbitleError.Rejected("Попытка входа устарела. Начните заново")
            }
            else -> CoreErrors.map(error)
        }
    }

    private fun rejection(step: AuthStep, key: String): String = when (step) {
        AuthStep.REQUEST_CODE -> "Не удалось отправить код. Проверьте номер телефона"
        AuthStep.VERIFY_CODE -> if ("expire" in key) "Код устарел. Запросите новый" else "Неверный код"
        AuthStep.PASSWORD -> "Неверный пароль"
        AuthStep.REGISTER -> "Не удалось создать аккаунт. Проверьте имя и попробуйте снова"
    }

    /** Код из SMS больше не действует: сессия сама запрашивает новый. */
    fun isExpiredCode(error: Throwable): Boolean {
        val failure = error as? CoreFailure ?: return false
        if (failure.kind == "SESSION_EXPIRED") return true
        return failure.kind == "SERVER" && failure.key?.lowercase()?.contains("expire") == true
    }

    /** Ключи сервера про лимиты попыток: точных ключей нет, поэтому по словам. */
    fun isRateLimit(key: String): Boolean = listOf("limit", "many", "flood", "attempt", "frequent").any { it in key }
}

/**
 * Ошибки смены почты восстановления. Неверный пароль идёт тем же путём, что пароль при входе.
 * Отказ на почте и коде — свой текст; ключ с `limit` — слишком много попыток.
 */
object TwoFactorErrors {
    private val REJECTION = setOf("AUTH", "SERVER", "NOT_FOUND")

    fun password(error: Throwable): OrbitleError = AuthErrors.map(error, AuthStep.PASSWORD)

    fun rejection(error: Throwable, message: String): OrbitleError {
        val failure = error as? CoreFailure
        if (failure != null && failure.kind in REJECTION) {
            if (failure.key?.lowercase()?.contains("limit") == true) return OrbitleError.Rejected(AuthErrors.TOO_MANY_ATTEMPTS)
            return OrbitleError.Rejected(message)
        }
        return CoreErrors.map(error)
    }
}
