package app.orbitle.presentation.chat

/**
 * Правила отметки прочтения, согласованные с iOS. Значения будут повторены в
 * test-fixtures/client-rules/constants.json: менять их нужно вместе.
 */
object ReadMarkRules {
    /** Отметка уходит через столько мс после последней смены кандидата: быстрая прокрутка шлёт одну. */
    const val DEBOUNCE_MS = 200L

    /**
     * Сообщение считается увиденным, когда видна хотя бы такая доля его высоты. Считается только
     * область ленты: без верхней панели, поля ввода и клавиатуры.
     */
    const val MIN_VISIBLE_FRACTION = 0.3f
}

/**
 * Строка ленты, как её видит список: [index] в порядке списка, [key] строки, смещение начала
 * [offset] и высота [size] в тех же единицах, что и границы видимой области.
 */
data class FeedItemFrame(val index: Int, val key: String?, val offset: Int, val size: Int)

/**
 * Какое сообщение ленты считается увиденным.
 *
 * Видимая область — только лента: верхняя панель, поле ввода и клавиатура уже снаружи неё,
 * а отступы содержимого ([beforeContent], [afterContent]) прячут строки под накладками внутри
 * ленты, поэтому в расчёт они не входят.
 *
 * Координаты — как у списка: смещения считаются от начала раскладки. У перевёрнутой ленты
 * ([reverseLayout]) начало — низ, и отступ «до содержимого» тоже нижний. Новые сообщения всегда
 * внизу: у перевёрнутой ленты это начало списка (меньший индекс), у обычной — конец.
 */
object ReadVisibility {

    /**
     * Ключ самого нового сообщения, у которого видно не меньше [ReadMarkRules.MIN_VISIBLE_FRACTION]
     * высоты. `null`, если такого нет.
     *
     * [viewportStart] и [viewportEnd] — границы видимой области списка. [beforeContent] — отступ
     * содержимого со стороны начала списка (у перевёрнутой ленты это низ, где поле ввода),
     * [afterContent] — со стороны конца (верх ленты, где плавающие накладки).
     */
    fun newestVisibleKey(
        items: List<FeedItemFrame>,
        viewportStart: Int,
        viewportEnd: Int,
        reverseLayout: Boolean,
        beforeContent: Int = 0,
        afterContent: Int = 0,
        minFraction: Float = ReadMarkRules.MIN_VISIBLE_FRACTION,
    ): String? {
        val start = viewportStart + beforeContent
        val end = viewportEnd - afterContent
        if (end <= start) return null
        val seen = items.filter { it.key != null && visibleFraction(it.offset, it.size, start, end) + 1e-4f >= minFraction }
        val newest = if (reverseLayout) seen.minByOrNull { it.index } else seen.maxByOrNull { it.index }
        return newest?.key
    }

    /** Какая доля высоты строки от [offset] размером [size] попадает в [start]…[end]. */
    fun visibleFraction(offset: Int, size: Int, start: Int, end: Int): Float {
        if (size <= 0 || end <= start) return 0f
        val shown = (minOf(offset + size, end) - maxOf(offset, start)).coerceAtLeast(0)
        return shown.toFloat() / size
    }
}
