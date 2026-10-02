package app.orbitle.presentation.chat

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
