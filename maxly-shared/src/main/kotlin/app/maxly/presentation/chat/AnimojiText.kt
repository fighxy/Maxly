package app.maxly.presentation.chat

import app.maxly.domain.TextSpan

/**
 * Где в тексте сообщения играют анимодзи (Lottie). Отметка `ANIMOJI` сервера несёт ссылку на
 * Lottie; если ссылки нет, она берётся из каталога анимодзи ([catalog]: эмодзи → ссылка).
 * Крупные эмодзи (сообщение из одних эмодзи) играют все, у кого есть анимация: по отметке,
 * иначе по каталогу — как в Max.
 */
object AnimojiText {
    /** Анимодзи в тексте: [from] и [length] в UTF-16, как у отметок. */
    data class Placed(val from: Int, val length: Int, val emoji: String, val lottieUrl: String)

    /** Анимодзи внутри обычного текста: только отмеченные, без отметки эмодзи остаются буквами. */
    fun inline(text: String, spans: List<TextSpan>, catalog: Map<String, String>): List<Placed> =
        spans.asSequence()
            .filter { it.kind == TextSpan.Kind.ANIMOJI }
            .mapNotNull { span ->
                val start = span.from.coerceIn(0, text.length)
                val end = (span.from + span.length).coerceIn(start, text.length)
                if (start >= end) return@mapNotNull null
                val emoji = text.substring(start, end)
                val url = span.url?.takeIf { it.isNotBlank() } ?: lookup(catalog, emoji) ?: return@mapNotNull null
                Placed(start, end - start, emoji, url)
            }
            .sortedBy { it.from }
            .toList()

    /**
     * Анимация для каждого из [emoji] — крупных эмодзи сообщения [text] по порядку; `null` —
     * эмодзи без анимации, рисуется буквой.
     */
    fun bigEmoji(text: String, emoji: List<String>, spans: List<TextSpan>, catalog: Map<String, String>): List<String?> {
        val marks = inline(text, spans, catalog)
        var cursor = 0
        return emoji.map { item ->
            val at = text.indexOf(item, cursor)
            if (at >= 0) cursor = at + item.length
            marks.firstOrNull { at >= 0 && it.from == at }?.lottieUrl ?: lookup(catalog, item)
        }
    }

    /** Ссылка из каталога: точное совпадение или без селектора вида `FE0F`. */
    fun lookup(catalog: Map<String, String>, emoji: String): String? {
        if (catalog.isEmpty()) return null
        catalog[emoji]?.let { return it }
        val bare = bare(emoji)
        catalog[bare]?.let { return it }
        return catalog.entries.firstOrNull { bare(it.key) == bare }?.value
    }

    /** Эмодзи без селектора вида `FE0F`. */
    fun bare(emoji: String): String = emoji.replace(VARIATION, "")

    private const val VARIATION = "️"
}

/**
 * Реакция, которую пользователь только что поставил. Её значок в плашке под сообщением один раз
 * проигрывает анимацию [lottieUrl] на месте, а вокруг — эффект [effectUrl] (`lottiePlayUrl`
 * анимодзи), крупнее значка; потом значок снова обычный. Так же, как в Komet.
 */
data class ReactionBurst(val messageId: String, val emoji: String, val lottieUrl: String?, val effectUrl: String?, val id: Long) {
    /** Это та плашка: то же сообщение и то же эмодзи (без учёта `FE0F`). */
    fun matches(messageId: String, emoji: String): Boolean =
        this.messageId == messageId && AnimojiText.bare(this.emoji) == AnimojiText.bare(emoji)
}
