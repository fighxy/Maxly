package app.orbitle.presentation.auth

import app.orbitle.domain.SessionRejection

/**
 * Что сказать, когда сервер отказал во входе по токену. [title] и [message] — текст сервера, а
 * если его нет — свой для каждой причины. [placement] — где его показать.
 */
data class LoginNotice(val title: String, val message: String?, val placement: Placement) {
    enum class Placement {
        /** Токен стёрт: экран входа, текст над полем номера. */
        LOGIN_FORM,
        /**
         * Токен цел (временный отказ): список чатов без сети, баннер над ним с «Повторить» и
         * «Выйти из аккаунта». Баннер уходит, когда клиент снова подключился.
         */
        CHAT_LIST_BANNER,
    }
}

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
            placement = if (rejection.tokenCleared) LoginNotice.Placement.LOGIN_FORM else LoginNotice.Placement.CHAT_LIST_BANNER,
        )
    }

    private fun fallback(reason: SessionRejection.Reason): Pair<String, String> = when (reason) {
        SessionRejection.Reason.TOKEN -> "Сессия завершена" to "Сервер больше не принимает этот вход. Войдите снова по номеру телефона"
        SessionRejection.Reason.BLOCKED -> "Аккаунт заблокирован" to "Сервер не пускает в этот аккаунт. Войти можно будет, когда блокировку снимут"
        SessionRejection.Reason.FLOOD -> "Слишком много входов" to "Сервер временно ограничил вход. Сохранённые чаты доступны без сети, повторите позже"
    }
}
