package app.orbitle.domain

import kotlinx.coroutines.flow.StateFlow

/** Шаг входа. Экран читает его из потока, а не из исключения. */
sealed interface AuthPhase {
    data object Restoring : AuthPhase
    data object SignedOut : AuthPhase
    data class CodeSent(val codeLength: Int?) : AuthPhase
    data class Password(val hint: String?) : AuthPhase
    data object Registration : AuthPhase
    data class SignedIn(val userId: String) : AuthPhase
    /** Сервер отклонил сохранённый токен. */
    data object Expired : AuthPhase
}

/** Соединение с сервером для баннера «Подключение…». */
enum class ConnectionState { CONNECTING, ONLINE, OFFLINE }

/**
 * Вход, восстановление и завершение сессии. Ошибки шагов приходят уже с русским текстом
 * ([OrbitleError.Rejected]). Ответ из отменённой попытки бросает [OrbitleError.Cancelled].
 */
interface AuthService {
    val phase: StateFlow<AuthPhase>
    val connection: StateFlow<ConnectionState>
    suspend fun restoreSession()
    suspend fun requestCode(phone: String)
    suspend fun resendCode()
    suspend fun verifyCode(code: String)
    suspend fun submitPassword(password: String)
    suspend fun register(firstName: String, lastName: String)
    /** Вернуться к вводу номера. После входа ничего не делает. */
    suspend fun cancelLogin()
    suspend fun logout()
}
