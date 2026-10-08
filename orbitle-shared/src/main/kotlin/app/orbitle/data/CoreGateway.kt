package app.orbitle.data

import kotlinx.coroutines.flow.Flow

/** Фаза ядра (`ClientState`) без подробностей ошибки. */
enum class CorePhase { IDLE, CONNECTING, AWAITING_AUTH, READY, RECONNECTING, TOKEN_REJECTED, FAILED }

/** Код из SMS запрошен: токен шага и длина кода, если сервер её прислал. */
data class CoreCode(val token: String, val codeLength: Int?)

/** Следующий шаг входа после кода, пароля или регистрации. */
sealed interface CoreAuthStep {
    data class LoggedIn(val userId: String) : CoreAuthStep
    data class Password(val trackId: String, val hint: String?) : CoreAuthStep
    data class Register(val token: String) : CoreAuthStep
}

/**
 * Ошибка ядра: [kind] — имя `ErrorKind` (`NETWORK`, `AUTH`, `SERVER`…), [key] — ключ сервера.
 */
class CoreFailure(
    val kind: String,
    val key: String?,
    message: String? = null,
    /** Текст ошибки от сервера для пользователя (`title`, иначе `localizedMessage`); `null` — не прислал. */
    val serverText: String? = null,
) : Exception(message ?: kind)

/**
 * Ядро в объёме, который нужен сессии. Реализация над `MaxClient` — [MaxCoreGateway];
 * тесты подставляют фейк. Методы бросают [CoreFailure].
 */
interface CoreGateway {
    val phases: Flow<CorePhase>
    fun hasStoredToken(): Boolean
    suspend fun start(): CorePhase
    fun currentUserId(): String
    suspend fun requestCode(phone: String, resend: Boolean): CoreCode
    suspend fun verifyCode(token: String, code: String): CoreAuthStep
    suspend fun checkPassword(trackId: String, password: String): CoreAuthStep
    suspend fun register(token: String, firstName: String, lastName: String): CoreAuthStep
    suspend fun logout()
    /** Последний отказ сервера во входе по токену ([CorePhase.TOKEN_REJECTED]); `null` — не было. */
    fun rejection(): app.orbitle.domain.SessionRejection? = null
}
