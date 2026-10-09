package app.maxly.presentation.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BubbleCornersTest {
    @Test
    fun cornersStayRoundWithoutATail() {
        val outContinued = BubbleCorners.of(outgoing = true, joinsPrevious = false, joinsNext = true)
        assertEquals(BubbleCorners.LARGE, outContinued.topStart)
        assertEquals(BubbleCorners.LARGE, outContinued.topEnd)
        assertEquals(BubbleCorners.LARGE, outContinued.bottomEnd)
        assertEquals(BubbleCorners.LARGE, outContinued.bottomStart)

        val outLast = BubbleCorners.of(outgoing = true, joinsPrevious = true, joinsNext = false)
        assertEquals(BubbleCorners.LARGE, outLast.topEnd)
        assertEquals(BubbleCorners.SMALL, outLast.bottomEnd)
        assertEquals(BubbleCorners.LARGE, outLast.topStart)
        assertEquals(BubbleCorners.LARGE, outLast.bottomStart)

        val incoming = BubbleCorners.of(outgoing = false, joinsPrevious = false, joinsNext = false)
        assertEquals(BubbleCorners.LARGE, incoming.topStart)
        assertEquals(BubbleCorners.SMALL, incoming.bottomStart)
        assertEquals(BubbleCorners.LARGE, incoming.topEnd)
        assertEquals(BubbleCorners.LARGE, incoming.bottomEnd)

        val incomingMiddle = BubbleCorners.of(outgoing = false, joinsPrevious = true, joinsNext = true)
        assertEquals(BubbleCorners.LARGE, incomingMiddle.topStart)
        assertEquals(BubbleCorners.LARGE, incomingMiddle.bottomStart)
        assertEquals(BubbleCorners.LARGE, incomingMiddle.topEnd)
        assertEquals(BubbleCorners.LARGE, incomingMiddle.bottomEnd)
    }

    @Test
    fun attachWindowIsFifteenMinutesForTheSameAuthorAndDay() {
        val window = BubbleCorners.ATTACH_WINDOW_MS
        assertEquals(15 * 60 * 1000L, window)
        assertEquals(430f, BubbleCorners.DESKTOP_MAX_DP)
        assertTrue(messagesAttach("2", 0L, "2", window, sameDay = true))
        assertFalse(messagesAttach("2", 0L, "2", window + 1, sameDay = true))
        assertFalse(messagesAttach("2", 0L, "3", 0L, sameDay = true))
        assertFalse(messagesAttach("2", 0L, "2", 0L, sameDay = false))
        assertFalse(messagesAttach("2", 0L, null, null, sameDay = true))
    }
}
