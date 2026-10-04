package app.orbitle.domain

/**
 * Ограничения аккаунта после входа на этом устройстве.
 *
 * Сервер Max временно ограничивает новый сеанс (облачный пароль, завершение других сеансов),
 * а новому аккаунту может ограничить сообщения и группы. Признака в ответе нет: клиент знает
 * только, как вошли и когда. Срок взят из клиента Komet: ограничения входа снимаются примерно
 * через сутки. У регистрации срока нет, сервер снимает их сам.
 */
data class AccountLimits(
    val entry: Entry,
    val grantedAtMs: Long,
    /** Панель после входа уже показана. */
    val shown: Boolean = false,
) {
    enum class Entry { LOGIN, REGISTRATION }

    /** Когда ограничения входа примерно снимутся. У регистрации срока нет. */
    val liftsAtMs: Long?
        get() = if (entry == Entry.LOGIN) grantedAtMs + LOGIN_LIMITS_MS else null

    /** Ограничения входа ещё действуют: строка в настройках видна. */
    fun isActive(nowMs: Long): Boolean = liftsAtMs?.let { nowMs < it } ?: false

    /** Показать панель на главном экране: ещё не показана и не устарела. */
    fun needsNotice(nowMs: Long): Boolean = !shown && (entry == Entry.REGISTRATION || isActive(nowMs))

    companion object {
        const val LOGIN_LIMITS_MS = 24 * 60 * 60 * 1000L
    }
}
