package app.orbitle.presentation.chat

import app.orbitle.domain.Message
import app.orbitle.presentation.common.PresenceText

/**
 * Выбор нескольких сообщений в ленте: подписи шапки и диалогов и текст для копирования.
 * Всё здесь — чистые функции, экран и [ChatViewModel] только подставляют данные.
 */
object MessageSelection {
    /** «1 сообщение», «3 сообщения», «11 сообщений». */
    fun countLabel(count: Int): String =
        "$count ${PresenceText.plural(count, "сообщение", "сообщения", "сообщений")}"

    /** Шапка в режиме выбора. */
    fun title(count: Int): String = countLabel(count)

    /** Заголовок подтверждения удаления: одно сообщение — как у меню сообщения. */
    fun deleteTitle(count: Int): String =
        if (count == 1) "Удалить сообщение?" else "Удалить ${countLabel(count)}?"

    /** Снекбар после пересылки. */
    fun forwardedNotice(count: Int): String =
        if (count == 1) "Сообщение переслано" else "Переслано: ${countLabel(count)}"

    /** Порядок ленты: от старых к новым, при равном времени — по id сервера. */
    val chronological: Comparator<Message> =
        compareBy<Message>({ it.timeMs }, { it.id.toLongOrNull() ?: Long.MAX_VALUE }, { it.id })

    /**
     * Текст выбранных сообщений для буфера обмена, от старых к новым. Одно сообщение — просто
     * его текст. Несколько — как переписка: перед каждым строка «Имя, ЧЧ:ММ», блоки через
     * пустую строку; у сообщения без текста — подпись вложения в квадратных скобках.
     */
    fun copyText(messages: List<Message>, time: (Long) -> String, name: (Message) -> String): String {
        val ordered = messages.sortedWith(chronological)
        if (ordered.isEmpty()) return ""
        if (ordered.size == 1) return ordered.single().displayText.trim()
        return ordered.joinToString("\n\n") { message ->
            val body = message.displayText.trim().ifEmpty { "[${message.replySnippet}]" }
            "${name(message)}, ${time(message.timeMs)}\n$body"
        }
    }
}
