package app.orbitle.presentation.chat

import app.orbitle.presentation.chat.RecordingGesture.Outcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceRecordingTest {
    @Test
    fun `levels follow the decibel scale`() {
        assertEquals(0f, VoiceWave.normalized(0f), 0f)
        assertEquals(1f, VoiceWave.normalized(1f), 0.0001f)
        assertEquals(0.6f, VoiceWave.normalized(0.1f), 0.0001f)
        assertEquals(0f, VoiceWave.normalized(0.001f), 0.0001f)
        assertEquals(1f, VoiceWave.peak(40_000), 0f)
    }

    @Test
    fun `wave has 80 bars of segment peaks`() {
        assertEquals(emptyList<Int>(), VoiceWave.wave(emptyList()))
        val peaks = List(160) { if (it < 80) 0f else 1f }
        val wave = VoiceWave.wave(peaks)
        assertEquals(80, wave.size)
        assertEquals(0, wave.first())
        assertEquals(120, wave.last())
        // Записи короче 80 отсчётов растягиваются повтором.
        val short = VoiceWave.wave(listOf(1f, 0f))
        assertEquals(80, short.size)
        assertEquals(120, short[0])
        assertEquals(0, short[79])
        assertTrue(short.all { it in 0..120 })
    }

    @Test
    fun `gesture sends, cancels and locks`() {
        assertEquals(Outcome.CONTINUE, RecordingGesture.during(-40f, -20f))
        assertEquals(Outcome.CANCEL, RecordingGesture.during(-130f, 0f))
        assertEquals(Outcome.LOCK, RecordingGesture.during(-10f, -95f))
        assertEquals(Outcome.SEND, RecordingGesture.released(-40f, 0f, 3_000))
        assertEquals(Outcome.CANCEL, RecordingGesture.released(-125f, 0f, 3_000))
        assertEquals(Outcome.CANCEL, RecordingGesture.released(0f, 0f, 300))
        assertEquals(0.5f, RecordingGesture.cancelProgress(-60f), 0.0001f)
    }
}
