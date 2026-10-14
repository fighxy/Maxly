package app.maxly.platform

/** Тексты значка в трее. */
object TrayText {
    const val OPEN = "Открыть Maxly"
    const val MUTE = "Без звука"
    const val EXIT = "Выход"

    /** Подсказка значка: «Maxly» или «Maxly — 3 непрочитанных». */
    fun tooltip(unread: Int): String = if (unread > 0) "Maxly — $unread ${unreadWord(unread)}" else "Maxly"

    /** «непрочитанное» после 1, 21…; «непрочитанных» после остальных чисел. */
    private fun unreadWord(n: Int): String {
        val tens = n % 100
        return if (n % 10 == 1 && tens != 11) "непрочитанное" else "непрочитанных"
    }

    /** Непрочитанные для значка: сумма счётчиков чатов, отмеченный непрочитанным без счётчика — один. */
    fun unread(chats: List<app.maxly.domain.Chat>): Int =
        chats.sumOf { if (it.unreadCount > 0) it.unreadCount else if (it.isMarkedUnread) 1 else 0 }
}
