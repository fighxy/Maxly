package app.maxly.presentation.chat

/**
 * Где стоит время с галочками внутри пузыря.
 * Ширину пузыря задаёт самый широкий блок (цитата, медиа, реакции, текст) — её здесь не трогаем.
 * Блок текста растягивается до ширины пузыря, и время встаёт в его правый нижний угол,
 * а не вплотную к короткой последней строке.
 */
object BubbleMetaLayout {
    /** Ширина пузыря: самый широкий блок, но не шире [maxWidth]. */
    fun bubbleWidth(blockWidths: List<Int>, maxWidth: Int): Int =
        (blockWidths.maxOrNull() ?: 0).coerceIn(0, maxWidth)

    /**
     * Минимальная ширина блока, который держит время: ширина остальных блоков пузыря,
     * чтобы время прижалось к краю пузыря. Не больше [maxWidth] — время не вылезет за край.
     */
    fun fillWidth(otherBlockWidths: List<Int>, maxWidth: Int): Int = bubbleWidth(otherBlockWidths, maxWidth)

    /** X времени внутри блока шириной [blockWidth]: к правому краю, но не левее начала. */
    fun metaX(blockWidth: Int, metaWidth: Int, endPadding: Int): Int =
        (blockWidth - endPadding - metaWidth).coerceAtLeast(0)
}
