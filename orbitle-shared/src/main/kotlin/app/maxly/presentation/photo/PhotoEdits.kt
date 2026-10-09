package app.maxly.presentation.photo

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Координаты относительно текущего кадра: одинаковые для превью и экспорта. */
data class PhotoPoint(val x: Float, val y: Float) {
    init { require(x.isFinite() && y.isFinite() && x in 0f..1f && y in 0f..1f) }
}

data class PhotoCrop(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    init {
        require(listOf(left, top, right, bottom).all { it.isFinite() && it in 0f..1f })
        require(right > left && bottom > top)
    }

    fun pixels(size: PhotoSize): PixelCrop {
        val x = (left * size.width).roundToInt().coerceIn(0, size.width - 1)
        val y = (top * size.height).roundToInt().coerceIn(0, size.height - 1)
        val endX = (right * size.width).roundToInt().coerceIn(x + 1, size.width)
        val endY = (bottom * size.height).roundToInt().coerceIn(y + 1, size.height)
        return PixelCrop(x, y, endX - x, endY - y)
    }

    companion object {
        val FULL = PhotoCrop(0f, 0f, 1f, 1f)
        fun between(a: PhotoPoint, b: PhotoPoint): PhotoCrop? =
            if (kotlin.math.abs(a.x - b.x) < .01f || kotlin.math.abs(a.y - b.y) < .01f) null
            else PhotoCrop(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))

        fun centered(size: PhotoSize, ratio: Float): PhotoCrop {
            require(ratio.isFinite() && ratio > 0)
            val actual = size.width.toFloat() / size.height
            val width = min(1f, ratio / actual)
            val height = min(1f, actual / ratio)
            return PhotoCrop((1 - width) / 2, (1 - height) / 2, (1 + width) / 2, (1 + height) / 2)
        }
    }
}

data class PixelCrop(val x: Int, val y: Int, val width: Int, val height: Int)
data class PhotoSize(val width: Int, val height: Int) {
    init { require(width > 0 && height > 0) }
    val shortest: Int get() = min(width, height)
}

/** Операции выполняются по порядку: последующий кадр/поворот затрагивает и подписи. */
sealed interface PhotoEdit {
    data class Crop(val rect: PhotoCrop) : PhotoEdit
    data class Rotate(val clockwise: Boolean = true) : PhotoEdit
    data object Flip : PhotoEdit
    data class Straighten(val degrees: Float) : PhotoEdit
    data class Stroke(val points: List<PhotoPoint>, val color: Int, val width: Float, val brush: PhotoBrush = PhotoBrush.PEN) : PhotoEdit {
        init { require(points.isNotEmpty() && width.isFinite() && width > 0) }
    }
    /** Размер шрифта — доля короткой стороны; позиция — левый верхний угол. */
    data class Text(val text: String, val point: PhotoPoint, val color: Int, val size: Float,
        val id: String = java.util.UUID.randomUUID().toString(), val style: PhotoTextStyle = PhotoTextStyle.OUTLINE,
        val font: PhotoFont = PhotoFont.SANS, val alignment: PhotoAlignment = PhotoAlignment.LEFT) : PhotoEdit {
        init { require(text.isNotBlank() && text.length <= 200 && size.isFinite() && size > 0) }
    }
    data class ReplaceText(val replacement: Text) : PhotoEdit
    data class RemoveText(val id: String) : PhotoEdit
    data class Shape(val rect: PhotoCrop, val shape: PhotoShape, val color: Int, val width: Float, val filled: Boolean) : PhotoEdit
    data class Adjust(val values: PhotoAdjustments) : PhotoEdit
    data class Filter(val preset: PhotoFilter, val amount: Float = 1f) : PhotoEdit {
        init { require(amount.isFinite() && amount in 0f..1f) }
    }
}

enum class PhotoBrush(val title: String) { PEN("Кисть"), ARROW("Стрелка"), MARKER("Маркер"), BLUR("Размытие"), ERASER("Ластик") }
enum class PhotoShape(val title: String) { RECTANGLE("Прямоугольник"), ELLIPSE("Эллипс") }
enum class PhotoTextStyle(val title: String) { OUTLINE("Контур"), PLAIN("Обычный"), SOLID("Подложка"), TRANSLUCENT("Полупрозрачный") }
enum class PhotoFont(val title: String) { SANS("Обычный"), SERIF("С засечками"), MONO("Моно"), ITALIC("Курсив") }
enum class PhotoAlignment(val title: String) { LEFT("Слева"), CENTER("По центру"), RIGHT("Справа") }

enum class PhotoFilter(val title: String) {
    MONO("Ч/б"), SEPIA("Сепия"), WARM("Тёплый"), COOL("Холодный"), CONTRAST("Контраст");

    fun pixel(argb: Int, amount: Float = 1f): Int {
        val r = ((argb ushr 16) and 255).toFloat()
        val g = ((argb ushr 8) and 255).toFloat()
        val b = (argb and 255).toFloat()
        val red: Float; val green: Float; val blue: Float
        when (this) {
            MONO -> { red = .299f * r + .587f * g + .114f * b; green = red; blue = red }
            SEPIA -> { red = .393f * r + .769f * g + .189f * b; green = .349f * r + .686f * g + .168f * b; blue = .272f * r + .534f * g + .131f * b }
            WARM -> { red = r + 20; green = g + 5; blue = b - 15 }
            COOL -> { red = r - 15; green = g + 3; blue = b + 20 }
            CONTRAST -> { red = (r - 128) * 1.25f + 128; green = (g - 128) * 1.25f + 128; blue = (b - 128) * 1.25f + 128 }
        }
        fun blend(original: Float, filtered: Float) = (original + (filtered.coerceIn(0f, 255f) - original) * amount).roundToInt().coerceIn(0, 255)
        return (argb and -0x1000000) or (blend(r, red) shl 16) or (blend(g, green) shl 8) or blend(b, blue)
    }
}

data class PhotoEditHistory(val edits: List<PhotoEdit> = emptyList(), val undone: List<PhotoEdit> = emptyList()) {
    fun add(edit: PhotoEdit) = PhotoEditHistory(edits + edit)
    fun undo() = if (edits.isEmpty()) this else PhotoEditHistory(edits.dropLast(1), undone + edits.last())
    fun redo() = if (undone.isEmpty()) this else PhotoEditHistory(edits + undone.last(), undone.dropLast(1))
    val resolved: List<PhotoEdit> get() {
        val replacements = edits.filterIsInstance<PhotoEdit.ReplaceText>().associate { it.replacement.id to it.replacement }
        val removed = edits.filterIsInstance<PhotoEdit.RemoveText>().map { it.id }.toSet()
        return edits.filterNot { it is PhotoEdit.ReplaceText || it is PhotoEdit.RemoveText || it is PhotoEdit.Text && it.id in removed }
            .map { if (it is PhotoEdit.Text) replacements[it.id] ?: it else it }
    }
    fun size(original: PhotoSize): PhotoSize = edits.fold(original) { size, edit ->
        when (edit) {
            is PhotoEdit.Rotate -> PhotoSize(size.height, size.width)
            is PhotoEdit.Crop -> edit.rect.pixels(size).let { PhotoSize(it.width, it.height) }
            else -> size
        }
    }
}
