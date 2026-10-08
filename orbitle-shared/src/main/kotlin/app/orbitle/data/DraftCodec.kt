package app.orbitle.data

import app.orbitle.domain.ChatDraft
import com.max.core.api.TextElementsJson

/**
 * Черновик в одной строке настроек: `v2⇥время⇥ответ⇥отметки⇥текст`. Отметки — JSON элементов
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
                if (text.isBlank()) return null
                val marks = runCatching { TextMarks.fromElements(TextElementsJson.parse(parts[3], text.length)) }.getOrDefault(emptyList())
                return ChatDraft(
                    text = text,
                    updatedAtMs = parts[1].toLongOrNull() ?: 0L,
                    formatting = marks.filter { it.from >= 0 && it.from + it.length <= text.length },
                    replyTo = parts[2].takeIf { it.isNotEmpty() },
                )
            }
        }
        val time = raw.substringBefore('\t').toLongOrNull() ?: 0L
        val text = raw.substringAfter('\t')
        return if (text.isBlank()) null else ChatDraft(text, time)
    }
}
