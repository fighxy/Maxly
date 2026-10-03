package app.orbitle.presentation.settings

/** Вход на другом устройстве по QR-коду. */
object QrLogin {
    const val FOOTER = "Откройте web.max.ru или MAX на компьютере и отсканируйте QR-код входа."
    const val NOT_LOGIN = "Это не QR-код входа в MAX"

    /**
     * Значение QR-кода как есть, без пробелов по краям. Разбирает и проверяет его сервер
     * (`AUTH_QR_APPROVE`): формат ссылки не документирован, поэтому клиент отсеивает только
     * пустые коды и явно не ссылки.
     */
    fun loginLink(value: String): String? {
        val text = value.trim()
        if (text.isEmpty() || text.any { it.isWhitespace() }) return null
        return text
    }
}
