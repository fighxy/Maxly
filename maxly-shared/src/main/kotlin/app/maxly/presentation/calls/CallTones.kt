package app.maxly.presentation.calls

import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/** Звуки звонка в PCM: 8 кГц, 16 бит, моно, little-endian. Платформа играет их по кругу. */
object CallTones {
    const val SAMPLE_RATE = 8_000

    /** Гудки исходящего: 425 Гц, секунда звука и четыре тишины, как на телефонных линиях. */
    fun ringback(): ByteArray = pcm(seconds = 5) { index ->
        if (index < SAMPLE_RATE) tone(index, 425.0, SAMPLE_RATE) else 0.0
    }

    /** Звонок входящего: два коротких сигнала 440/480 Гц и пауза, всего 3 секунды. */
    fun ringtone(): ByteArray = pcm(seconds = 3) { index ->
        val burst = SAMPLE_RATE * 4 / 10
        val gap = SAMPLE_RATE / 5
        when {
            index < burst -> (tone(index, 440.0, burst) + tone(index, 480.0, burst)) / 2
            index in (burst + gap) until (2 * burst + gap) -> {
                val local = index - burst - gap
                (tone(local, 440.0, burst) + tone(local, 480.0, burst)) / 2
            }
            else -> 0.0
        }
    }

    /** Синус с плавными краями (20 мс), чтобы не щёлкал. */
    private fun tone(index: Int, frequency: Double, length: Int): Double {
        val fade = min(1.0, min(index, length - index).toDouble() / 160)
        return sin(2 * PI * frequency * index / SAMPLE_RATE) * fade
    }

    private fun pcm(seconds: Int, sample: (Int) -> Double): ByteArray {
        val count = SAMPLE_RATE * seconds
        val out = ByteArray(count * 2)
        for (index in 0 until count) {
            val value = (sample(index) * 9_000).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            out[index * 2] = (value and 0xFF).toByte()
            out[index * 2 + 1] = (value shr 8 and 0xFF).toByte()
        }
        return out
    }
}
