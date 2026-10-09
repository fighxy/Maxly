package app.maxly.presentation.chatlist

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatListHeaderGeometryTest {
    private val header = ChatListHeaderGeometry(stories = 100f, search = 50f, stackSlack = 8f)

    @Test
    fun scrollingUpHidesSearchThenPinsFolders() {
        assertEquals(130f, header.scrolled(100f, -30f, fling = false))
        assertFalse(header.foldersPinned(130f))
        assertEquals(150f, header.scrolled(130f, -80f, fling = true))
        assertTrue(header.foldersPinned(150f))
    }

    @Test
    fun flingStopsAtSearchButFingerOpensStories() {
        assertEquals(100f, header.scrolled(140f, 90f, fling = true))
        assertEquals(100f, header.scrolled(100f, 20f, fling = true))
        assertEquals(80f, header.scrolled(100f, 20f, fling = false))
        assertEquals(0f, header.scrolled(80f, 200f, fling = false))
        // Истории уже выглядывают — инерция их не прячет и не держит.
        assertEquals(40f, header.scrolled(60f, 20f, fling = true))
    }

    @Test
    fun stackShowsWhileStoriesBarelyPeek() {
        assertTrue(header.storiesHidden(100f))
        assertTrue(header.storiesHidden(93f))
        assertFalse(header.storiesHidden(90f))
        assertTrue(ChatListHeaderGeometry(0f, 50f).storiesHidden(0f))
    }

    @Test
    fun snapsToTheNearestEdge() {
        assertEquals(0f, header.snapTarget(40f))
        assertEquals(100f, header.snapTarget(60f))
        assertEquals(100f, header.snapTarget(120f))
        assertEquals(150f, header.snapTarget(130f))
        assertNull(header.snapTarget(100f))
        assertNull(header.snapTarget(150f))
    }

    @Test
    fun loadedStoriesStayHidden() {
        val before = ChatListHeaderGeometry(stories = 0f, search = 50f)
        assertEquals(100f, header.remeasured(0f, before))
        assertEquals(120f, header.remeasured(20f, before))
        // Открытые истории сменили высоту — список не прыгает.
        assertEquals(30f, header.remeasured(30f, ChatListHeaderGeometry(80f, 50f, 8f)))
    }
}
