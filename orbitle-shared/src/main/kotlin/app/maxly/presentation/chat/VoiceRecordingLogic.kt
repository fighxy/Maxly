package app.maxly.presentation.chat

import kotlin.math.log10
import kotlin.math.roundToInt

/** Волна записи: 80 столбиков, пик каждого отрезка, 0…120 — как в iOS-версии. */
object VoiceWave {
    const val BARS = 80
    const val TOP = 120

    /** Пик 0…1 → уровень 0…1 по шкале −50…0 дБ. */
    fun normalized(peak: Float): Float {
        if (peak <= 0f) return 0f
        val db = 20f * log10(peak)
        return ((db + 50f) / 50f).coerceIn(0f, 1f)
    }

    /** Амплитуда записи 0…32767 → пик 0…1. */
    fun peak(amplitude: Int): Float = (amplitude / 32767f).coerceIn(0f, 1f)

    fun wave(peaks: List<Float>, bars: Int = BARS): List<Int> {
        if (peaks.isEmpty()) return emptyList()
        return (0 until bars).map { index ->
            val start = index * peaks.size / bars
            val end = minOf(peaks.size, maxOf(start + 1, (index + 1) * peaks.size / bars))
            val peak = peaks.subList(start, end).max()
            (normalized(peak) * TOP).roundToInt()
        }
    }
}

/**
 * Жест кнопки микрофона: удержание — запись, отпустить — отправить, увести палец влево —
 * отмена, вверх — закрепить запись, тогда палец можно убрать.
 */
object RecordingGesture {
    /** Сдвиги в dp. */
    const val CANCEL_DISTANCE = 120f
    const val LOCK_DISTANCE = 90f
    /** Короче — запись не отправляется, а подсказывает «Удерживайте». */
    const val MINIMUM_DURATION_MS = 600L
    const val HOLD_HINT = "Удерживайте, чтобы записать голосовое"

    enum class Outcome { SEND, CANCEL, LOCK, CONTINUE }

    /** Что значит положение пальца ([dx], [dy] в dp, влево и вверх — меньше нуля). */
    fun during(dx: Float, dy: Float): Outcome = when {
        dx <= -CANCEL_DISTANCE -> Outcome.CANCEL
        dy <= -LOCK_DISTANCE -> Outcome.LOCK
        else -> Outcome.CONTINUE
    }

    /** Палец отпущен: отправить или отменить. */
    fun released(dx: Float, dy: Float, durationMs: Long): Outcome = when {
        during(dx, dy) == Outcome.CANCEL -> Outcome.CANCEL
        durationMs < MINIMUM_DURATION_MS -> Outcome.CANCEL
        else -> Outcome.SEND
    }

    /** Насколько близка отмена, 0…1 — для подсказки «Влево — отмена». */
    fun cancelProgress(dx: Float): Float = (-dx / CANCEL_DISTANCE).coerceIn(0f, 1f)
}
