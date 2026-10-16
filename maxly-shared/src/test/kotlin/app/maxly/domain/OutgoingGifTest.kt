package app.maxly.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OutgoingGifTest {
    @Test
    fun gifMimeKeepsGifExtension() {
        assertEquals("cat.gif", OutgoingFile.nameFor("cat.gif", "image/gif"))
        assertEquals("cat.gif", OutgoingFile.nameFor("cat.jpg", "image/gif"))
        assertEquals("1000123.gif", OutgoingFile.nameFor("1000123", "image/gif"))
        assertEquals("photo.jpg", OutgoingFile.nameFor("photo.jpg", "image/jpeg"))
    }

    @Test
    fun gifIsPhotoKind() {
        assertEquals(OutgoingFile.Kind.PHOTO, OutgoingFile.kindOf("image/gif"))
        assertTrue(OutgoingFile("/c/a.GIF", "a.GIF", OutgoingFile.Kind.PHOTO).isGif)
        assertFalse(OutgoingFile("/c/a.png", "a.png", OutgoingFile.Kind.PHOTO).isGif)
        assertFalse(OutgoingFile("/c/a.gif", "a.gif", OutgoingFile.Kind.FILE).isGif)
    }
}
