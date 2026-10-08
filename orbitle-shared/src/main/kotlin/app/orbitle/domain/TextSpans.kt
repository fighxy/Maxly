package app.orbitle.domain

/**
 * Правила отметок текста, общие с iOS (`test-fixtures/formatting`): что уходит на сервер из поля
 * ввода и когда правка ничего не меняет. Смещения — единицы UTF-16, как у сервера.
 */
object TextSpans {
    /**
     * Текст поля и его отметки в том виде, в каком они уходят: текст без пробелов и переводов
     * строк по краям, отметки сдвинуты на срезанное начало и обрезаны по новым краям, пустые
     * выпадают. Пересекающиеся и смежные отметки одного вида сливаются (ссылки — только с тем
     * же адресом); упоминания и анимодзи — отдельные знаки со своими данными, не сливаются.
     * Порядок — по началу, затем по виду ([TextSpan.Kind]), затем по длине.
     */
    fun serialize(draft: String, spans: List<TextSpan>): Pair<String, List<TextSpan>> {
        val lead = draft.length - draft.trimStart().length
        val text = draft.trim()
        val shifted = spans.mapNotNull { span ->
            val from = (span.from - lead).coerceAtLeast(0)
            val end = (span.from + span.length - lead).coerceAtMost(text.length)
            if (span.length > 0 && end > from) span.copy(from = from, length = end - from) else null
        }
        return text to normalize(shifted)
    }

    /**
     * Правка сообщения [originalText] с отметками [originalSpans] ничего не меняет: текст после
     * обрезки и отметки (обе стороны — по [serialize]) совпали. Тогда запрос не нужен.
     */
    fun unchanged(originalText: String, originalSpans: List<TextSpan>, text: String, spans: List<TextSpan>): Boolean {
        val (beforeText, before) = serialize(originalText, originalSpans)
        val (afterText, after) = serialize(text, spans)
        return beforeText == afterText && before.toSet() == after.toSet()
    }

    /** Слияние одного вида и порядок, как в [serialize]; отрицательные и пустые отрезки выпадают. */
    fun normalize(spans: List<TextSpan>): List<TextSpan> {
        val valid = spans.filter { it.length > 0 && it.from >= 0 }
        val (single, mergeable) = valid.partition { it.kind == TextSpan.Kind.ANIMOJI || it.kind == TextSpan.Kind.MENTION }
        val merged = ArrayList<TextSpan>(single.distinct())
        for ((_, group) in mergeable.groupBy { it.kind to it.url }) {
            var current: TextSpan? = null
            for (span in group.sortedBy { it.from }) {
                val open = current
                current = if (open != null && span.from <= open.from + open.length) {
                    open.copy(length = maxOf(open.from + open.length, span.from + span.length) - open.from)
                } else {
                    open?.let(merged::add)
                    span
                }
            }
            current?.let(merged::add)
        }
        return merged.sortedWith(ORDER)
    }

    /** Порядок отметок: по началу, по виду, по длине. */
    val ORDER: Comparator<TextSpan> = compareBy({ it.from }, { it.kind.ordinal }, { it.length })
}
