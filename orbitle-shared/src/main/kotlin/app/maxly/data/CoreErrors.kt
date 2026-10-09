package app.maxly.data

import app.maxly.domain.MaxlyError
import kotlinx.coroutines.CancellationException

/**
 * Перевод ошибок ядра в категории UI. Текст ошибки от сервера (`title` / `localizedMessage`)
 * идёт первым, свои тексты — запасные.
 */
object CoreErrors {
    /** Запасной текст, когда об ошибке сказать нечего. */
    const val UNKNOWN_TEXT = "Что-то пошло не так"

    fun map(error: Throwable): MaxlyError {
        if (error is MaxlyError) return error
        if (error is CancellationException) return MaxlyError.Cancelled
        val failure = error as? CoreFailure ?: return MaxlyError.Unknown
        return when (failure.kind) {
            "NETWORK", "TIMEOUT", "CLOSED" -> MaxlyError.NetworkUnavailable
            "SESSION_EXPIRED" -> MaxlyError.AuthExpired
            // Отказ шага входа переводит AuthErrors, а вне входа это отклонённый запрос.
            "AUTH", "NOT_FOUND" -> failure.serverText?.let(MaxlyError::Rejected) ?: MaxlyError.InvalidRequest
            "SERVER", "UPLOAD" -> MaxlyError.Server(failure.key ?: failure.kind, failure.serverText)
            // Сервер ответил без нужных полей: это его сбой, а не ошибка пользователя.
            "MALFORMED_REPLY" -> MaxlyError.Server(failure.kind)
            "CANCELLED" -> MaxlyError.Cancelled
            else -> MaxlyError.Unknown
        }
    }

    /**
     * Текст ошибки для экрана, где у действия есть свой текст [fallback]: сначала текст сервера,
     * затем текст уже переведённой ошибки ([MaxlyError.userMessage]), затем [fallback].
     */
    fun text(error: Throwable, fallback: String = UNKNOWN_TEXT): String =
        serverText(error) ?: (error as? MaxlyError)?.userMessage ?: fallback

    /** Текст, который прислал сервер, если он есть у [error]. */
    fun serverText(error: Throwable): String? = when (error) {
        is CoreFailure -> error.serverText
        is MaxlyError -> error.serverText
        else -> null
    }
}

/** Шаг входа, на котором упал вызов ядра. От него зависит текст ошибки. */
enum class AuthStep { REQUEST_CODE, VERIFY_CODE, PASSWORD, REGISTER }

/**
 * Ошибки шагов входа с русским текстом для экрана. Неверный код приходит как `SERVER`,
 * неверный пароль как `AUTH`, поэтому один и тот же вид значит разное на разных шагах.
 * Если сервер прислал свой текст, показывается он; свои тексты — запасные.
 */
object AuthErrors {
    const val TOO_MANY_ATTEMPTS = "Слишком много попыток. Подождите немного и попробуйте снова"

    fun map(error: Throwable, step: AuthStep): MaxlyError {
        if (error is MaxlyError) return error
        val failure = error as? CoreFailure ?: return CoreErrors.map(error)
        val key = failure.key?.lowercase().orEmpty()
        val server = failure.serverText
        return when (failure.kind) {
            "AUTH", "SERVER", "NOT_FOUND" -> MaxlyError.Rejected(
                server ?: if (isRateLimit(key)) TOO_MANY_ATTEMPTS else rejection(step, key),
            )
            "SESSION_EXPIRED" -> MaxlyError.Rejected(
                server ?: when (step) {
                    AuthStep.VERIFY_CODE -> "Код устарел. Запросите новый"
                    else -> "Попытка входа устарела. Начните заново"
                },
            )
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
 * Отказ на почте и коде — текст сервера, иначе свой; ключ с `limit` — слишком много попыток.
 */
object TwoFactorErrors {
    private val REJECTION = setOf("AUTH", "SERVER", "NOT_FOUND")

    fun password(error: Throwable): MaxlyError = AuthErrors.map(error, AuthStep.PASSWORD)

    fun rejection(error: Throwable, message: String): MaxlyError {
        val failure = error as? CoreFailure
        if (failure != null && failure.kind in REJECTION) {
            failure.serverText?.let { return MaxlyError.Rejected(it) }
            if (failure.key?.lowercase()?.contains("limit") == true) return MaxlyError.Rejected(AuthErrors.TOO_MANY_ATTEMPTS)
            return MaxlyError.Rejected(message)
        }
        return CoreErrors.map(error)
    }
}
