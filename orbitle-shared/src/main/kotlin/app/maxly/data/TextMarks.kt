package app.maxly.data

import app.maxly.domain.TextSpan
import app.maxly.domain.TextSpans
import com.max.core.api.TextElement
import com.max.core.api.TextElementType

/**
 * Отметки текста клиента ([TextSpan]) и элементы ядра ([TextElement]) — одно и то же в двух видах.
 * Наружу уходят только элементы: схему `elements` знает ядро.
 */
object TextMarks {
    /**
     * Отметки [text] как элементы ядра, по порядку в тексте ([TextSpans.ORDER]). Отрезки за пределами текста,
     * ссылки без адреса, упоминания и анимодзи без числового id пропускаются; незнакомые типы
     * уходят как пришли, с новыми смещениями.
     */
    fun toElements(text: String, spans: List<TextSpan>): List<TextElement> = spans
        .sortedWith(TextSpans.ORDER)
        .mapNotNull { element(it) }
        .filter { it.fits(text.length) }

    /**
     * Элементы ядра обратно в отметки (входящие сообщения, черновики с сервера), в порядке
     * сервера, без слияния. Известный тип не зависит от регистра; незнакомый хранится как есть
     * ([TextSpan.Kind.UNKNOWN], тип с его регистром и все данные элемента); ссылки без адреса
     * пропускаются. С длиной текста [textLength] хвост за концом обрезается, а начатые за концом
     * отрезки выпадают.
     */
    fun fromElements(elements: List<TextElement>, textLength: Int? = null): List<TextSpan> =
        elements.mapNotNull { span(it, textLength) }

    /**
     * `elements` сервера как есть (`{type, from, length, attributes?, entityId?}`) в отметки по
     * тексту [text]: разбор ядра ([TextElement.parseAll]: нет `from` — 0, нет `length` — до конца
     * текста, числа строками), затем [fromElements]. Без текста элементы без `length` выпадают.
     */
    fun fromRaw(raw: List<*>?, text: String?): List<TextSpan> {
        if (text != null && text.isEmpty()) return emptyList()
        return fromElements(TextElement.parseAll(raw, text?.length), text?.length)
    }

    private fun element(span: TextSpan): TextElement? = when (span.kind) {
        TextSpan.Kind.STRONG -> TextElement.strong(span.from, span.length)
        TextSpan.Kind.EMPHASIZED -> TextElement.emphasized(span.from, span.length)
        TextSpan.Kind.UNDERLINE -> TextElement.underline(span.from, span.length)
        TextSpan.Kind.STRIKETHROUGH -> TextElement.strikethrough(span.from, span.length)
        TextSpan.Kind.MONOSPACED -> TextElement.monospaced(span.from, span.length)
        TextSpan.Kind.HEADING -> TextElement.heading(span.from, span.length)
        TextSpan.Kind.QUOTE -> TextElement.quote(span.from, span.length)
        TextSpan.Kind.LINK -> span.url?.takeIf { it.isNotBlank() }?.let { TextElement.link(span.from, span.length, it) }
        TextSpan.Kind.MENTION -> span.userId?.toLongOrNull()?.let { TextElement.mention(span.from, span.length, it) }
        TextSpan.Kind.ANIMOJI -> span.entityId?.toLongOrNull()?.let { TextElement.animoji(span.from, span.length, it, span.url.orEmpty()) }
        // Чужая разметка уходит как пришла, с новыми смещениями.
        TextSpan.Kind.UNKNOWN -> span.foreign?.copy(from = span.from, length = span.length)
    }

    private fun span(element: TextElement, textLength: Int?): TextSpan? {
        val kind = KINDS[element.type.uppercase()] ?: TextSpan.Kind.UNKNOWN
        val from = element.from
        if (from < 0 || element.length <= 0) return null
        val length = if (textLength == null) element.length else minOf(element.length, textLength - from)
        if (length <= 0) return null
        val attributes = element.attributes
        return when (kind) {
            TextSpan.Kind.MENTION -> (element.entityId ?: number(attributes["userId"]))?.let {
                TextSpan(kind, from, length, userId = it.toString())
            }
            TextSpan.Kind.ANIMOJI -> element.entityId?.let {
                val lottie = element.animojiLottieUrl ?: (attributes["lottieUrl"] as? String)?.takeIf { url -> url.isNotEmpty() }
                TextSpan(kind, from, length, url = lottie, entityId = it.toString())
            }
            TextSpan.Kind.LINK -> element.url?.let { TextSpan(kind, from, length, url = it) }
            TextSpan.Kind.UNKNOWN -> TextSpan(kind, from, length, foreign = element.copy(from = 0, length = 0))
            else -> TextSpan(kind, from, length)
        }
    }

    private fun number(value: Any?): Long? = when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull()
        else -> null
    }

    private val KINDS: Map<String, TextSpan.Kind> = mapOf(
        TextElementType.STRONG to TextSpan.Kind.STRONG,
        TextElementType.EMPHASIZED to TextSpan.Kind.EMPHASIZED,
        TextElementType.UNDERLINE to TextSpan.Kind.UNDERLINE,
        TextElementType.STRIKETHROUGH to TextSpan.Kind.STRIKETHROUGH,
        TextElementType.MONOSPACED to TextSpan.Kind.MONOSPACED,
        TextElementType.CODE to TextSpan.Kind.MONOSPACED,
        TextElementType.HEADING to TextSpan.Kind.HEADING,
        TextElementType.QUOTE to TextSpan.Kind.QUOTE,
        TextElementType.LINK to TextSpan.Kind.LINK,
        TextElementType.USER_MENTION to TextSpan.Kind.MENTION,
        TextElementType.ANIMOJI to TextSpan.Kind.ANIMOJI,
    )
}
