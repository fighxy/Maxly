package app.orbitle.presentation.chat

import app.orbitle.domain.CallContent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CallBubbleTextTest {
    private fun call(hangup: String, ms: Long, video: Boolean = false, link: String? = null) =
        CallContent(id = "c", durationMs = ms, isVideo = video, hangupType = hangup, joinLink = link)

    @Test
    fun titles() {
        assertEquals("Исходящий звонок", CallBubbleText.title(call("HUNGUP", 1_000), true))
        assertEquals("Входящий звонок", CallBubbleText.title(call("HUNGUP", 1_000), false))
        assertEquals("Входящий видеозвонок", CallBubbleText.title(call("HUNGUP", 1_000, video = true), false))
        assertEquals("Пропущенный звонок", CallBubbleText.title(call("MISSED", 0), false))
        assertEquals("Пропущенный видеозвонок", CallBubbleText.title(call("REJECTED", 0, video = true), false))
        assertEquals("Отменённый звонок", CallBubbleText.title(call("CANCELED", 0), true))
        assertEquals("Отклонённый звонок", CallBubbleText.title(call("REJECTED", 0), true))
        assertEquals("Групповой звонок", CallBubbleText.title(call("HUNGUP", 1_000, link = "https://call.example/j/x"), true))
        assertEquals("Групповой видеозвонок", CallBubbleText.title(call("MISSED", 0, video = true, link = "https://call.example/j/x"), false))
    }

    @Test
    fun durations() {
        assertEquals("0:42", CallBubbleText.duration(call("HUNGUP", 42_000)))
        assertEquals("12:05", CallBubbleText.duration(call("HUNGUP", 725_999)))
        assertEquals("1:02:03", CallBubbleText.duration(call("HUNGUP", 3_723_000)))
        assertEquals("0:09", CallBubbleText.duration(call("HUNGUP", 9_000)))
        assertNull(CallBubbleText.duration(call("MISSED", 0)))
        assertNull(CallBubbleText.duration(call("CANCELED", 4_000)))
    }

    @Test
    fun alertAndIcons() {
        assertTrue(CallBubbleText.isAlert(call("MISSED", 0), false))
        assertFalse(CallBubbleText.isAlert(call("CANCELED", 0), true))
        assertFalse(CallBubbleText.isAlert(call("HUNGUP", 1_000), false))
        assertEquals(CallBubbleText.Icon.OUTGOING, CallBubbleText.icon(call("HUNGUP", 1_000), true))
        assertEquals(CallBubbleText.Icon.INCOMING, CallBubbleText.icon(call("HUNGUP", 1_000), false))
        assertEquals(CallBubbleText.Icon.PHONE_DOWN, CallBubbleText.icon(call("MISSED", 0), false))
        assertEquals(CallBubbleText.Icon.VIDEO_OFF, CallBubbleText.icon(call("MISSED", 0, video = true), false))
        assertEquals(CallBubbleText.Icon.VIDEO, CallBubbleText.icon(call("HUNGUP", 1_000, video = true), false))
    }

    @Test
    fun accessibility() {
        assertEquals("Исходящий звонок, длительность 0:42, 12:30", CallBubbleText.accessibility(call("HUNGUP", 42_000), true, "12:30"))
        assertEquals("Пропущенный звонок", CallBubbleText.accessibility(call("MISSED", 0), false, ""))
    }
}
