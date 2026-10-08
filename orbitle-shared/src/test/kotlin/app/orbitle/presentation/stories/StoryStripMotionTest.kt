package app.orbitle.presentation.stories

import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StoryStripMotionTest {
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
