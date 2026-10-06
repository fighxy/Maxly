package app.orbitle.presentation.stories

import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StoryStripMotionTest {
    private val height = 100f
    private val threshold = 48f

    @Test
    fun liftFromTheTopCollapsesPastTheThreshold() {
        assertEquals(0.6f, StoryStripMotion.reveal(true, -40f, height, atTop = true), 0.001f)
        assertTrue(StoryStripMotion.settledExpanded(true, -40f, atTop = true, threshold))
        assertEquals(0.4f, StoryStripMotion.reveal(true, -60f, height, atTop = true), 0.001f)
        assertFalse(StoryStripMotion.settledExpanded(true, -60f, atTop = true, threshold))
    }

    @Test
    fun pullDownFromTheTopOpensAHiddenStrip() {
        assertEquals(0.3f, StoryStripMotion.reveal(false, 30f, height, atTop = true), 0.001f)
        assertFalse(StoryStripMotion.settledExpanded(false, 30f, atTop = true, threshold))
        assertTrue(StoryStripMotion.settledExpanded(false, 48f, atTop = true, threshold))
    }

    @Test
    fun scrollInTheMiddleDoesNotMoveTheStrip() {
        assertEquals(1f, StoryStripMotion.reveal(true, -80f, height, atTop = false))
        assertTrue(StoryStripMotion.settledExpanded(true, -80f, atTop = false, threshold))
        assertEquals(0f, StoryStripMotion.reveal(false, 80f, height, atTop = false))
        assertFalse(StoryStripMotion.settledExpanded(false, 80f, atTop = false, threshold))
    }

    @Test
    fun wrongDirectionDoesNotMove() {
        assertEquals(1f, StoryStripMotion.reveal(true, 40f, height, atTop = true))
        assertEquals(0f, StoryStripMotion.reveal(false, -40f, height, atTop = true))
    }

    @Test
    fun refreshOnlyWhenTheStripIsAlreadyOpen() {
        assertTrue(StoryStripMotion.refreshesOnPull(true))
        assertFalse(StoryStripMotion.refreshesOnPull(false))
    }

    @Test
    fun groupRingRequiresTheChatOwnerType() {
        val group = StoryRing(StoryOwner("10", StoryOwner.Type.CHAT), "Группа", null, 1, 1, 0)
        val person = StoryRing(StoryOwner("10"), "Иван", null, 1, 1, 0)
        assertTrue(StoryStripMotion.ringMatches(person, StoryOwner.Type.USER))
        assertTrue(StoryStripMotion.ringMatches(group, StoryOwner.Type.CHAT))
        assertFalse(StoryStripMotion.ringMatches(person, StoryOwner.Type.CHAT))
        assertFalse(StoryStripMotion.ringMatches(group, StoryOwner.Type.CHANNEL))
        assertFalse(StoryStripMotion.ringMatches(null, StoryOwner.Type.USER))
    }
}
