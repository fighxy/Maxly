package app.maxly.presentation.media

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Элементы интерфейса просмотра фото и видео — порт iOS `MediaViewerChrome`.
 * Одиночное касание прячет и показывает их; у играющего ролика они уходят сами через
 * [AUTO_HIDE_MS]; на паузе, в конце ролика и пока тянут полосу — видны.
 */
class MediaViewerChrome(visible: Boolean = true) {
    var visible: Boolean = visible
        private set

    fun toggle() { visible = !visible }
    fun show() { visible = true }
    fun hide() { visible = false }

    /** Ролик встал (пауза, конец, ошибка): элементы нужны, чтобы продолжить. */
    fun playbackStopped() { visible = true }

    fun shouldAutoHide(playing: Boolean, scrubbing: Boolean, menuOpen: Boolean): Boolean =
        visible && playing && !scrubbing && !menuOpen

    companion object {
        const val AUTO_HIDE_MS = 3_000L

        /** Без состояния: прятать ли по таймеру (для экранов, что держат флаг сами). */
        fun shouldAutoHide(visible: Boolean, playing: Boolean, scrubbing: Boolean, menuOpen: Boolean): Boolean =
            visible && playing && !scrubbing && !menuOpen
    }
}

/**
 * Двойное касание у края ролика: −10 / +10 секунд. Касания подряд в пределах [WINDOW_MS]
 * складываются: третье — уже 20 секунд. Порт iOS `SeekTapAccumulator`.
 */
class SeekTapAccumulator {
    data class Seek(val targetMs: Long, val totalSeconds: Int, val forward: Boolean)

    private var last: Long? = null
    private var forward = true
    private var total = 0

    fun tap(forward: Boolean, nowMs: Long, positionMs: Long, durationMs: Long): Seek {
        val previous = last
        total = if (previous != null && nowMs - previous <= WINDOW_MS && forward == this.forward) total + STEP_SECONDS else STEP_SECONDS
        last = nowMs
        this.forward = forward
        val raw = positionMs + if (forward) STEP_SECONDS * 1_000L else -STEP_SECONDS * 1_000L
        val upper = if (durationMs > 0) durationMs else maxOf(raw, 0)
        return Seek(raw.coerceIn(0, upper), total, forward)
    }

    fun isActive(nowMs: Long): Boolean = last?.let { nowMs - it <= WINDOW_MS } == true

    companion object {
        const val STEP_SECONDS = 10
        const val WINDOW_MS = 800L
        const val EDGE = 0.35f

        /** Касание в точке [x] из ширины [width]: `false` — левый край, `true` — правый, `null` — середина. */
        fun side(x: Float, width: Float): Boolean? = when {
            width <= 0f -> null
            x < width * EDGE -> false
            x > width * (1 - EDGE) -> true
            else -> null
        }
    }
}

/** Смахивание просмотра: закрыть или вернуть кадр, и как гаснет фон. Порт iOS `MediaDismissRule`. */
object MediaDismissRule {
    const val DISTANCE_FRACTION = 0.15f
    /** Скорость броска, dp в секунду. */
    const val FLICK_VELOCITY = 800f
    const val MINIMUM_FLICK = 40f

    /** [offset], [height] — в dp, [velocity] — dp/с. */
    fun shouldClose(offset: Float, velocity: Float, height: Float): Boolean {
        val distance = abs(offset)
        if (height <= 0f) return distance > 120f
        if (distance > height * DISTANCE_FRACTION) return true
        return distance > MINIMUM_FLICK && abs(velocity) > FLICK_VELOCITY && (velocity > 0) == (offset > 0)
    }

    fun backgroundAlpha(offset: Float, height: Float): Float =
        if (height <= 0f) 1f else maxOf(0.2f, 1f - abs(offset) / height * 1.6f)
}

/** Скорость ролика: меню 0,5…2× и удержание — 2×. */
object PlaybackSpeed {
    val options = listOf(0.5f, 1f, 1.25f, 1.5f, 2f)
    const val HOLD = 2f

    fun label(rate: Float): String {
        val hundredths = (rate * 100).roundToInt()
        val text = if (hundredths % 100 == 0) (hundredths / 100).toString()
        else (hundredths / 100.0).toString().trimEnd('0').replace('.', ',')
        return "$text×"
    }
}

/** Время ролика и загрузка: «0:07», «1:02:03», «-0:42», «37 %», «12,5 из 50,0 МБ». */
object MediaTimeText {
    fun clock(ms: Long): String {
        if (ms < 0) return "0:00"
        val total = ms / 1_000
        val hours = total / 3_600
        val minutes = total / 60 % 60
        val seconds = total % 60
        return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
    }

    fun remaining(positionMs: Long, durationMs: Long): String =
        if (durationMs <= 0) "–:––" else "-" + clock(maxOf(0, durationMs - positionMs))

    fun download(fraction: Float, totalBytes: Long? = null): String {
        val clamped = if (fraction.isNaN()) 0f else fraction.coerceIn(0f, 1f)
        if (totalBytes == null || totalBytes <= 0) return "${(clamped * 100).roundToInt()} %"
        val total = totalBytes / 1_048_576.0
        return "${megabytes(total * clamped)} из ${megabytes(total)} МБ"
    }

    private fun megabytes(value: Double): String = "%.1f".format(java.util.Locale.ROOT, value).replace('.', ',')
}
