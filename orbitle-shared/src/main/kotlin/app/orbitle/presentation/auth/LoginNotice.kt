package app.orbitle.presentation.auth

import app.orbitle.domain.SessionRejection

/**
 * Что сказать, когда сервер отказал во входе по токену. [title] и [message] — текст сервера, а
 * если его нет — свой для каждой причины. [blocking] — временный отказ: вместо формы входа экран
 * ожидания с «Повторить» и «Выйти».
 */
data class LoginNotice(val title: String, val message: String?, val blocking: Boolean)

object LoginNotices {
    /**
     * Текст отказа [rejection]. Первым идёт текст сервера: заголовок (`title`) и пояснение
     * (`localizedMessage`, иначе `description`). Чего сервер не прислал, дополняет свой текст
     * причины; пояснение своё — только когда от сервера нет ни заголовка, ни пояснения.
     */
    fun of(rejection: SessionRejection): LoginNotice {
        val serverTitle = rejection.title?.trim()?.takeIf { it.isNotEmpty() }
        val serverBody = listOf(rejection.localizedMessage, rejection.description)
            .firstNotNullOfOrNull { text -> text?.trim()?.takeIf { it.isNotEmpty() } }
            ?.takeIf { it != serverTitle }
        val (title, body) = fallback(rejection.reason)
        return LoginNotice(
            title = serverTitle ?: title,
            message = serverBody ?: if (serverTitle == null) body else null,
            blocking = !rejection.tokenCleared,
        )
    }

    private fun fallback(reason: SessionRejection.Reason): Pair<String, String> = when (reason) {
        SessionRejection.Reason.TOKEN -> "Сессия завершена" to "Сервер больше не принимает этот вход. Войдите снова по номеру телефона"
        SessionRejection.Reason.BLOCKED -> "Аккаунт заблокирован" to "Сервер не пускает в этот аккаунт. Войти можно будет, когда блокировку снимут"
        SessionRejection.Reason.FLOOD -> "Слишком много входов" to "Сервер временно ограничил вход. Попробуйте позже: сеанс сохранён"
    }
}
