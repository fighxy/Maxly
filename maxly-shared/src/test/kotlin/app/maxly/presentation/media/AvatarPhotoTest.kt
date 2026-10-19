package app.maxly.presentation.media

import app.maxly.domain.ChatAttachment
import com.maxly.core.media.ImageShape
import com.maxly.core.media.ImageSizes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

class AvatarPhotoTest {
    private val base = "https://i.oneme.ru/i?r=BTGBPUwtwgYUeoFhO7rESmr8"

    @Test
    fun originalIsTheCoreUrlWithoutSize() {
        assertEquals(base, AvatarPhoto.original(base))
        assertEquals(base, AvatarPhoto.original(ImageSizes.url(base, ImageSizes.SQUARE_MAX)))
        assertEquals(base, AvatarPhoto.original("$base&fn=sqr_96&fn=w_480"))
    }

    @Test
    fun originalKeepsOtherParameters() {
        assertEquals("https://cdn/a?r=1&expires=1760000000000", AvatarPhoto.original("https://cdn/a?fn=sqr_192&r=1&expires=1760000000000"))
        assertEquals("https://cdn/a", AvatarPhoto.original("https://cdn/a?fn=sqr_192"))
        // Ядро дописывает `&fn=` и к адресу без `?`.
        assertEquals("https://cdn/a", AvatarPhoto.original("https://cdn/a&fn=sqr_64"))
        assertEquals("https://cdn/a&t=2", AvatarPhoto.original("https://cdn/a&fn=sqr_64&t=2"))
    }

    @Test
    fun noPhotoNoOriginal() {
        assertNull(AvatarPhoto.original(null))
        assertNull(AvatarPhoto.original(""))
        assertNull(AvatarPhoto.original("   "))
        assertEquals("file:///data/a.jpg", AvatarPhoto.original("file:///data/a.jpg"))
    }

    @Test
    fun previewIsTheHeaderSquare() {
        // 104 dp × 2,75 = 286 px: первый шаг не меньше — sqr_288.
        val preview = AvatarPhoto.preview("$base&fn=sqr_64", 104f, 2.75f)
        assertEquals(ImageSizes.sizedUrl(base, ImageShape.SQUARE, 286), preview)
        assertEquals("sqr_288", preview!!.substringAfter("fn="))
        assertNull(AvatarPhoto.preview(null, 104f, 2f))
    }

    @Test
    fun viewerOpensTheOriginalWithThePreviewFirst() {
        val preview = AvatarPhoto.preview(base, 104f, 2f)
        val viewer = AvatarPhoto.viewer("42", "$base&fn=sqr_96", "  Анна Смирнова ", preview)!!
        val photo = (viewer.items.single() as ChatAttachment.Photo).photo
        assertEquals(base, photo.url)
        assertEquals(preview, viewer.previews[photo.id])
        assertEquals("Анна Смирнова", viewer.authorName)
        assertEquals(0, viewer.index)
        assertTrue(AvatarPhoto.isAvatar(viewer))
        assertFalse(AvatarPhoto.isAvatar(viewer.copy(messageId = "5")))
        assertFalse(AvatarPhoto.isAvatar(null))
    }

    @Test
    fun noAvatarOpensNothing() {
        assertNull(AvatarPhoto.viewer("42", null, "Анна"))
        assertNull(AvatarPhoto.viewer("42", "", "Анна"))
    }

    @Test
    fun cacheIdChangesWithTheUrl() {
        val a = AvatarPhoto.cacheId("-7001", "$base")
        val b = AvatarPhoto.cacheId("-7001", "${base}x")
        assertTrue(a.startsWith("avatar-7001-"))
        assertTrue(a.all { it.isLetterOrDigit() || it == '-' })
        assertFalse(a == b)
    }

    private val time = java.time.LocalDateTime.of(2026, 10, 19, 15, 43, 0).toInstant(ZoneOffset.UTC).toEpochMilli()

    @Test
    fun saveNameCarriesTitleAndTime() {
        assertEquals("Фото профиля — Анна Смирнова 2026-10-19 15.43.00.jpg", AvatarPhoto.fileName("Анна  Смирнова", time, "jpg", ZoneOffset.UTC))
        assertEquals("Фото профиля 2026-10-19 15.43.00.png", AvatarPhoto.fileName("  ", time, "png", ZoneOffset.UTC))
        assertEquals("Фото профиля — Канал_ новости 2026-10-19 15.43.00.webp", AvatarPhoto.fileName("Канал: новости", time, "webp", ZoneOffset.UTC))
        assertEquals("Фото профиля 2026-10-19 15.43.00.jpg", AvatarPhoto.fileName("", time, "", ZoneOffset.UTC))
    }

    @Test
    fun saveNameIsShortAndSafe() {
        val name = AvatarPhoto.fileName("а/б\\в".repeat(40), time, "jpg", ZoneOffset.UTC)
        assertFalse(name.contains('/') || name.contains('\\'))
        assertTrue(name.length < 120)
        assertTrue(name.endsWith(" 2026-10-19 15.43.00.jpg"))
    }

    @Test
    fun chosenFileGetsTheRealImageExtension() {
        assertEquals("/home/me/Анна.jpg", AvatarPhoto.chosenFile("/home/me/Анна.jpg", "jpg"))
        assertEquals("/home/me/Анна.JPEG", AvatarPhoto.chosenFile("/home/me/Анна.JPEG", "jpg"))
        assertEquals("/home/me/Анна.png", AvatarPhoto.chosenFile("/home/me/Анна.jpg", "png"))
        assertEquals("/home/me/Анна.png", AvatarPhoto.chosenFile("/home/me/Анна", "png"))
        assertEquals("/home/me/Анна.jpg", AvatarPhoto.chosenFile("/home/me/Анна.", "jpg"))
        assertEquals("/home/me/Анна.bin", AvatarPhoto.chosenFile("/home/me/Анна.bin", "jpg"))
        assertEquals("C:\\Users\\me\\a.jpg", AvatarPhoto.chosenFile("C:\\Users\\me\\a", "jpg"))
        assertEquals("/home/me.d/a.jpg", AvatarPhoto.chosenFile("/home/me.d/a", "jpg"))
    }
}
