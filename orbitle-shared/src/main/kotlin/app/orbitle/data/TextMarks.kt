package app.orbitle.data

import app.orbitle.domain.TextSpan
import com.max.core.api.TextElement
import com.max.core.api.TextElementType

/**
 * Отметки текста клиента ([TextSpan]) и элементы ядра ([TextElement]) — одно и то же в двух видах.
 * Наружу уходят только элементы: схему `elements` знает ядро.
 */
object TextMarks {
    /**
     * Отметки [text] как элементы ядра, по порядку в тексте. Отрезки за пределами текста,
     * ссылки без адреса, упоминания и анимодзи без числового id пропускаются.
     */
    fun toElements(text: String, spans: List<TextSpan>): List<TextElement> = spans
        .mapNotNull { element(it) }
        .filter { it.fits(text.length) }
        .sortedBy { it.from }

    /** Элементы ядра обратно в отметки (черновики с сервера). Незнакомые типы пропускаются. */
    fun fromElements(elements: List<TextElement>): List<TextSpan> = elements.mapNotNull { span(it) }

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
    }

    private fun span(element: TextElement): TextSpan? {
        val kind = KINDS[element.type] ?: return null
        if (element.from < 0 || element.length <= 0) return null
        return when (kind) {
            TextSpan.Kind.MENTION -> element.entityId?.let { TextSpan(kind, element.from, element.length, userId = it.toString()) }
            TextSpan.Kind.ANIMOJI -> element.entityId?.let {
                TextSpan(kind, element.from, element.length, url = element.animojiLottieUrl, entityId = it.toString())
            }
            TextSpan.Kind.LINK -> element.url?.let { TextSpan(kind, element.from, element.length, url = it) }
            else -> TextSpan(kind, element.from, element.length)
        }
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
