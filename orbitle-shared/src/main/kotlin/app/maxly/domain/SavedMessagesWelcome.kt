package app.maxly.domain

/**
 * Приветствие «Избранного»: сервер кладёт в чат [Chat.SAVED_MESSAGES_ID] сообщение,
 * текст которого — ключ локализации, а не готовая фраза. Показывать его как есть нельзя:
 * список чатов заменяет его подсказкой, лента чата прячет.
 */
object SavedMessagesWelcome {
    const val KEY = "welcome.saved.dialog.message"

    /** Текст — тот самый ключ (пробелы и переводы строк по краям не мешают). */
    fun isKey(text: String?): Boolean = text != null && text.trim() == KEY

    /** Приветствие в «Избранном»; в других чатах такой текст показывается как обычный. */
    fun matches(chatId: String, text: String?): Boolean = chatId == Chat.SAVED_MESSAGES_ID && isKey(text)
}
