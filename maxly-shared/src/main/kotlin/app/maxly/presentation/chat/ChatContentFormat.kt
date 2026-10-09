package app.maxly.presentation.chat

import kotlin.math.floor
import kotlin.math.roundToInt

/** Размеры и подписи содержимого пузыря. */
object ChatContentFormat {
    private val calmWave = listOf(40, 90, 140, 200, 120, 70, 160, 220, 100, 60, 180, 130, 50, 150, 210, 80)

    /** Высоты 0.12…1: дорожка сервера, сжатая (максимум корзины) или растянутая (интерполяция) под [count]. */
    fun waveBars(samples: List<Int>, count: Int = 28): List<Double> {
        val source = samples.ifEmpty { calmWave }
        val buckets = maxOf(count, 1)
        val raw = ArrayList<Double>(buckets)
        if (buckets <= source.size) {
            for (index in 0 until buckets) {
                val start = index * source.size / buckets
                val end = minOf(source.size, maxOf(start + 1, (index + 1) * source.size / buckets))
                raw += (source.subList(start, end).maxOrNull() ?: 0).toDouble()
            }
        } else {
            val last = source.size - 1
            for (index in 0 until buckets) {
                val position = if (buckets > 1) index.toDouble() * last / (buckets - 1) else 0.0
                val low = floor(position).toInt()
                val high = minOf(low + 1, last)
                val t = position - low
                raw += source[low] * (1 - t) + source[high] * t
            }
        }
        val peak = maxOf(raw.maxOrNull() ?: 0.0, 1.0)
        return raw.map { (it / peak).coerceIn(0.12, 1.0) }
    }

    data class Frame(val width: Double, val height: Double)

    /** Рамка кадра: широкие не становятся лентой, высокие не уезжают за экран. */
    fun frame(pixelWidth: Int?, pixelHeight: Int?, maxWidth: Double, maxHeight: Double = 420.0): Frame {
        val widthLimit = maxOf(120.0, maxWidth)
        val wide = (pixelWidth ?: 0).toDouble()
        val high = (pixelHeight ?: 0).toDouble()
        val ratio = if (wide > 0 && high > 0) (wide / high).coerceIn(0.45, 1.91) else 1.0
        var width = widthLimit
        var height = width / ratio
        if (height > maxHeight) {
            height = maxHeight
            width = height * ratio
        }
        return Frame(width, height)
    }

    /** Байты, КБ, МБ, ГБ; одна дробная цифра через запятую. */
    fun fileSize(bytes: Long): String {
        val value = maxOf(0L, bytes)
        if (value < 1024) return "$value Б"
        val units = listOf("КБ", "МБ", "ГБ")
        var size = value.toDouble()
        var unit = -1
        while (size >= 1024 && unit < units.size - 1) {
            size /= 1024
            unit += 1
        }
        val tenths = (size * 10).roundToInt()
        val whole = tenths / 10
        val fraction = tenths % 10
        return if (fraction == 0) "$whole ${units[unit]}" else "$whole,$fraction ${units[unit]}"
    }

    /**
     * Сообщение из одних эмодзи (от одного до трёх, пробелы не в счёт). `null` — обычный текст.
     * Символ со своим видом эмодзи, либо последовательность (флаг, тон кожи, ZWJ, `FE0F`).
     * Цифра и `#` одним скаляром сюда не попадают.
     */
    fun bigEmoji(text: String, limit: Int = 3): List<String>? {
        val found = ArrayList<String>(limit)
        var index = 0
        while (index < text.length) {
            val cp = text.codePointAt(index)
            if (Character.isWhitespace(cp)) {
                index += Character.charCount(cp)
                continue
            }
            val end = emojiEnd(text, index)
            if (end <= index || found.size >= limit) return null
            found += text.substring(index, end)
            index = end
        }
        return found.takeIf { it.isNotEmpty() }
    }

    /** Размер крупных эмодзи: одно — крупнее всего. */
    fun bigEmojiSize(count: Int): Int = when (count) {
        1 -> 64
        2 -> 52
        else -> 44
    }

    private fun emojiEnd(text: String, start: Int): Int {
        val first = text.codePointAt(start)
        var index = start + Character.charCount(first)
        if (isRegional(first)) {
            if (index < text.length && isRegional(text.codePointAt(index))) {
                index += Character.charCount(text.codePointAt(index))
            }
            return index
        }
        if (isKeycapBase(first)) {
            val after = variation(text, index)
            if (after < text.length && text.codePointAt(after) == KEYCAP) return after + Character.charCount(KEYCAP)
            return start
        }
        if (!isEmojiPresentation(first)) return start
        index = skin(text, index)
        index = variation(text, index)
        while (index < text.length && text.codePointAt(index) == ZWJ) {
            val next = index + 1
            if (next >= text.length || !isEmojiPresentation(text.codePointAt(next))) break
            index = next + Character.charCount(text.codePointAt(next))
            index = skin(text, index)
            index = variation(text, index)
        }
        return index
    }

    private fun skin(text: String, index: Int): Int =
        if (index < text.length && text.codePointAt(index) in 0x1F3FB..0x1F3FF) index + Character.charCount(text.codePointAt(index)) else index

    private fun variation(text: String, index: Int): Int =
        if (index < text.length && text.codePointAt(index) == FE0F) index + 1 else index

    private fun isKeycapBase(cp: Int) = cp in 0x30..0x39 || cp == '#'.code || cp == '*'.code

    private fun isRegional(cp: Int) = cp in 0x1F1E6..0x1F1FF

    private fun isEmojiPresentation(cp: Int): Boolean {
        if (cp in 0x1F300..0x1FAFF || isRegional(cp)) return true
        if (cp in 0x2600..0x27BF) return true
        if (cp == 0x231A || cp == 0x231B || cp == 0x2328 || cp == 0x23CF) return true
        if (cp in 0x23E9..0x23F3 || cp in 0x23F8..0x23FA) return true
        if (cp == 0x24C2 || cp in 0x25AA..0x25AB || cp == 0x25B6 || cp == 0x25C0 || cp in 0x25FB..0x25FE) return true
        if (cp == 0x2934 || cp == 0x2935 || cp in 0x2B05..0x2B07 || cp == 0x2B1B || cp == 0x2B1C || cp == 0x2B50 || cp == 0x2B55) return true
        if (cp == 0x3030 || cp == 0x303D || cp == 0x3297 || cp == 0x3299) return true
        return false
    }

    private const val FE0F = 0xFE0F
    private const val ZWJ = 0x200D
    private const val KEYCAP = 0x20E3
}

/** Столбики дорожки голосового по ширине пузыря: остаток делится между зазорами. */
data class WaveformLayout(val width: Double, val barWidth: Double, val step: Double, val count: Int) {

    fun x(index: Int): Double = index * step

    /** Столбик закрашен, если его середина уже прозвучала. */
    fun isPlayed(index: Int, progress: Double): Boolean {
        if (progress <= 0 || width <= 0) return false
        if (progress >= 1) return true
        return x(index) + barWidth / 2 <= progress * width
    }

    /** Доля дорожки под пальцем, 0…1. */
    fun progressAt(x: Double): Double {
        if (width <= 0 || !x.isFinite()) return 0.0
        return (x / width).coerceIn(0.0, 1.0)
    }

    fun heights(samples: List<Int>): List<Double> = ChatContentFormat.waveBars(samples, count)

    companion object {
        fun of(width: Double, barWidth: Double = 3.0, spacing: Double = 2.0): WaveformLayout {
            val w = maxOf(0.0, width)
            val bar = maxOf(0.5, minOf(barWidth, maxOf(w, 0.5)))
            val gap = maxOf(0.0, spacing)
            val count = maxOf(1, floor((w + gap) / (bar + gap)).toInt())
            return WaveformLayout(w, bar, if (count > 1) (w - bar) / (count - 1) else 0.0, count)
        }
    }
}
