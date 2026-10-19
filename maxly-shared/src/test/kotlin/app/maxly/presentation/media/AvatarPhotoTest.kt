package app.maxly.presentation.media

import app.maxly.domain.ChatAttachment
import com.maxly.core.media.ImageSizes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

class AvatarPhotoTest {
    private val base = "https://i.oneme.ru/i?r=BTGBPUwtwgYUeoFhO7rESmr8"

    private val raw = "https://i.oneme.ru/i?r=RAWaaaa"
    private val thumb = "$base&fn=sqr_96"

    @Test
    fun fullUrlFirstThenViewerUrlsLargestFirst() {
        val full = ImageSizes.originalUrl(raw, thumb)
        val viewer = ImageSizes.viewerUrls(raw, thumb)
        val urls = AvatarPhoto.candidates(full, viewer)
        assertEquals(raw, urls.first())
        assertEquals(viewer, urls.drop(1))
        assertEquals("$raw&fn=w_1440", urls[1])
        assertEquals("$raw&fn=sqr_720", urls[2])
        assertEquals("$base&fn=w_1440", urls[3])
        assertEquals("$base&fn=sqr_64", urls.last())
        // Квадрат шапки как пришёл (с его `fn`) не берётся вместо оригинала.
        assertFalse(thumb in urls.take(urls.indexOf("$base&fn=sqr_96")))
    }

    @Test
    fun withoutRawTheBaseOriginalLeads() {
        val urls = AvatarPhoto.candidates(ImageSizes.originalUrl(null, thumb), ImageSizes.viewerUrls(null, thumb))
        assertEquals(listOf(base, "$base&fn=w_1440", "$base&fn=sqr_720"), urls.take(3))
    }

    @Test
    fun candidatesDropBlanksAndRepeats() {
        assertEquals(listOf("https://cdn/a", "https://cdn/a&fn=w_1440"), AvatarPhoto.candidates(" https://cdn/a ", listOf("", "https://cdn/a", "https://cdn/a&fn=w_1440")))
        assertEquals(listOf("https://cdn/a&fn=w_1440"), AvatarPhoto.candidates(null, listOf("https://cdn/a&fn=w_1440")))
        assertTrue(AvatarPhoto.candidates(null, emptyList()).isEmpty())
        assertTrue(AvatarPhoto.candidates("  ", emptyList()).isEmpty())
        assertEquals(listOf("file:///data/a.jpg"), AvatarPhoto.candidates("file:///data/a.jpg", listOf("https://cdn/a&fn=w_1440")))
    }

    @Test
    fun firstLoadedWalksTheChainInOrder() = kotlinx.coroutines.runBlocking {
        val tried = mutableListOf<String>()
        val found = AvatarPhoto.firstLoaded(listOf("full", "w_1440", "sqr_720", "w_1080")) { url ->
            tried += url
            if (url == "sqr_720") "file-$url" else throw java.io.IOException("404")
        }
        assertEquals("sqr_720" to "file-sqr_720", found)
        assertEquals(listOf("full", "w_1440", "sqr_720"), tried)
        assertNull(AvatarPhoto.firstLoaded(listOf("a", "b")) { throw java.io.IOException("404") })
    }

    @Test
    fun expiredWhenAnyUrlIsPastItsDeadline() {
        assertTrue(AvatarPhoto.isExpired(listOf("https://cdn/a?r=1&expires=1000"), 1000))
        assertFalse(AvatarPhoto.isExpired(listOf("https://cdn/a?r=1&expires=1000"), 999))
        assertFalse(AvatarPhoto.isExpired(listOf("https://cdn/a?r=1"), Long.MAX_VALUE))
    }

    @Test
    fun historySkipsTheCurrentPhotoAndKeepsServerOrder() {
        val current = AvatarPhoto.current("42", base, ImageSizes.viewerUrls(null, base))!!
        val frames = AvatarPhoto.history("42", listOf(7L to "$base&fn=sqr_192", 6L to "https://cdn/old?r=2", 5L to "https://cdn/older?r=3&fn=w_480"), 7L, current)
        assertEquals(listOf("avatar-42-6", "avatar-42-5"), frames.map { it.id })
        assertEquals("https://cdn/older?r=3", frames[1].urls.first())
        assertEquals("https://cdn/older?r=3&fn=w_1440", frames[1].urls[1])
        assertEquals("https://cdn/older?r=3&fn=w_480", frames[1].preview)
        // Без id совпадающий с текущим адрес тоже пропускается.
        assertEquals(listOf("avatar-42-n1"), AvatarPhoto.history("42", listOf(null to "$base&fn=sqr_96", null to "https://cdn/old"), null, current).map { it.id })
    }

    @Test
    fun viewerShowsCurrentFirstWithItsChain() {
        val current = AvatarPhoto.current("42", base, listOf("$base&fn=w_1440"), preview = thumb)!!
        val old = AvatarPhoto.Frame("avatar-42-6", listOf("https://cdn/old", "https://cdn/old&fn=w_1440"))
        val viewer = AvatarPhoto.viewer("42", listOf(current, old), "  Анна Смирнова ")!!
        assertEquals(listOf("avatar-42", "avatar-42-6"), viewer.items.map { it.id })
        assertEquals(base, (viewer.items[0] as ChatAttachment.Photo).photo.url)
        assertEquals(listOf(base, "$base&fn=w_1440"), viewer.fallbacks["avatar-42"])
        assertEquals(thumb, viewer.previews["avatar-42"])
        assertEquals("Анна Смирнова", viewer.authorName)
        assertEquals(0, viewer.index)
        assertTrue(AvatarPhoto.isAvatar(viewer))
        assertFalse(AvatarPhoto.isAvatar(viewer.copy(messageId = "5")))
        assertFalse(AvatarPhoto.isAvatar(null))
    }

    @Test
    fun noAvatarOpensNothing() {
        assertNull(AvatarPhoto.current("42", null, emptyList()))
        assertNull(AvatarPhoto.viewer("42", emptyList(), "Анна"))
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
