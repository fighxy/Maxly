package app.maxly.presentation.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrollDownTest {
    @Test
    fun `button hides while the newest message is on screen`() {
        assertFalse(ScrollDown.isVisible(listOf(0, 1, 2), 40))
        assertFalse(ScrollDown.isVisible(emptyList(), 0))
        assertTrue(ScrollDown.isVisible(listOf(1, 2, 3), 40))
        assertTrue(ScrollDown.isVisible(listOf(12, 13), 40))
    }
}
