package app.maxly.data

import app.maxly.domain.ChatDraft
import com.maxly.core.api.TextElementsJson

/**
 * Черновик в одной строке настроек: `v2⇥время⇥ответ⇥отметки⇥текст` (текст может быть пуст, если
 * есть ответ). Отметки — JSON элементов
 * ядра ([TextElementsJson]), текст последним: в нём бывают табуляции. Старая запись
 * `время⇥текст` читается без отметок.
 */
object DraftCodec {
    private const val VERSION = "v2"

    fun encode(draft: ChatDraft): String {
        val marks = TextElementsJson.write(TextMarks.toElements(draft.text, draft.formatting))
        return listOf(VERSION, draft.updatedAtMs.toString(), draft.replyTo.orEmpty(), marks, draft.text).joinToString("\t")
    }

    /** `null` — пустой черновик. */
    fun decode(raw: String): ChatDraft? {
        if (raw.startsWith("$VERSION\t")) {
            val parts = raw.split('\t', limit = 5)
            if (parts.size == 5) {
                val text = parts[4]
                val reply = parts[2].takeIf { it.isNotEmpty() }
                // Ответ без текста — тоже черновик.
                if (text.isBlank() && reply == null) return null
                // Отметки по тексту: хвост за концом обрезается, отметка за концом выпадает (как с сервера).
                val marks = runCatching { TextMarks.fromElements(TextElementsJson.parse(parts[3], text.length), text.length) }.getOrDefault(emptyList())
                return ChatDraft(
                    text = text,
                    updatedAtMs = parts[1].toLongOrNull() ?: 0L,
                    formatting = marks,
                    replyTo = reply,
                )
            }
        }
        val time = raw.substringBefore('\t').toLongOrNull() ?: 0L
        val text = raw.substringAfter('\t')
        return if (text.isBlank()) null else ChatDraft(text, time)
    }
}
