package app.maxly.presentation.chat

import app.maxly.MainDispatcherRule
import app.maxly.domain.ChatAttachment
import app.maxly.domain.FileContent
import app.maxly.domain.Message
import app.maxly.domain.MessageContent
import app.maxly.domain.PhotoContent
import app.maxly.domain.VideoContent
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class MediaSavingTest {
    @get:Rule val main = MainDispatcherRule()

    private class Saver : MediaSaver {
        val saved = mutableListOf<Pair<String, SavedKind>>()
        val directories = mutableListOf<String?>()
        val pictures = mutableListOf<String>()
        var failure: Exception? = null
        override suspend fun savePicture(path: String, name: String) {
            failure?.let { throw it }
            pictures += name
        }
        override suspend fun save(path: String, name: String, kind: SavedKind, directory: String?) {
            failure?.let { throw it }
            saved += name to kind
            directories += directory
        }
    }

    private class Files : MessageFiles {
        val urls = mutableListOf<String>()
        override fun cached(fileId: String, name: String): String? = null
        override suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit): String {
            urls += url
            return "/nonexistent/$fileId/$name"
        }
    }

    private val repo = object : app.maxly.data.MessageRepository by FakeMessages() {
        override suspend fun mediaLink(chatId: String, messageId: String, attachment: ChatAttachment) = "https://cdn/video-${attachment.id}"
    }
    private val saver = Saver()
    private val files = Files()
    private val notices = mutableListOf<String>()
    private val errors = mutableListOf<Exception>()
    private val media = ChatMedia("10", repo, TestScope(UnconfinedTestDispatcher()), null, files, saver, onNotice = { notices += it }) { errors += it }

    private val time = java.time.LocalDateTime.of(2026, 10, 1, 14, 5, 33).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
    private fun msg(vararg attachments: ChatAttachment, id: String = "5") =
        Message(id, "10", "2", "", time, content = MessageContent(attachments = attachments.toList()))

    @Test
    fun savesPhotosAndVideosToGallery() {
        val m = msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1")), ChatAttachment.Video(VideoContent("v1", null)))
        assertTrue(media.canSave(m, SaveTarget.GALLERY))
        assertFalse(media.canSave(m, SaveTarget.DOWNLOADS))
        media.save(m, SaveTarget.GALLERY)
        assertEquals(listOf("https://cdn/p1", "https://cdn/video-v1"), files.urls)
        assertEquals(listOf("Maxly 2026-10-01 14.05.33.jpg" to SavedKind.IMAGE, "Maxly 2026-10-01 14.05.33 2.mp4" to SavedKind.VIDEO), saver.saved)
        assertEquals(listOf("Сохранено в галерею"), notices)
        assertTrue(media.state.value.saving.isEmpty())
    }

    @Test
    fun savesFilesToDownloadsUnderTheirNames() {
        val m = msg(ChatAttachment.File(FileContent("f1", "отчёт.pdf", url = "https://cdn/f1")))
        media.save(m, SaveTarget.DOWNLOADS)
        assertEquals(listOf("отчёт.pdf" to SavedKind.OTHER), saver.saved)
        assertEquals(listOf("Сохранено в «Загрузки»"), notices)
    }

    @Test
    fun savesIntoAChosenFolder() {
        val m = msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1")))
        media.save(m, SaveTarget.GALLERY, directory = "/home/me/Pictures")
        assertEquals(listOf<String?>("/home/me/Pictures"), saver.directories)
        assertEquals(listOf("Сохранено в папку «Pictures»"), notices)
    }

    @Test
    fun noticeNamesThePlaceOfThePlatform() {
        val downloads = object : MediaSaver {
            override suspend fun save(path: String, name: String, kind: SavedKind, directory: String?) = Unit
            override fun place(kind: SavedKind) = "«Загрузки»"
        }
        val desktop = ChatMedia("10", repo, TestScope(UnconfinedTestDispatcher()), null, files, downloads, onNotice = { notices += it }) { errors += it }
        desktop.save(msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1"))), SaveTarget.GALLERY)
        assertEquals(listOf("Сохранено в «Загрузки»"), notices)
    }

    @Test
    fun webpAndHeicAreTranscodedUnderAFreeName() {
        assertTrue(SaveNaming.needsTranscode("Maxly 2026-10-01 14.05.33.webp"))
        assertTrue(SaveNaming.needsTranscode("a.HEIC"))
        assertFalse(SaveNaming.needsTranscode("a.jpg"))
        assertFalse(SaveNaming.needsTranscode("webp"))
        assertEquals("Maxly 1.jpg", SaveNaming.withExtension("Maxly 1.webp", "jpg"))
        assertEquals("photo.png", SaveNaming.withExtension("photo", "png"))
        val taken = setOf("a.jpg", "a 2.jpg")
        assertEquals("a 3.jpg", SaveNaming.freeName("a.jpg") { it in taken })
        assertEquals("b.jpg", SaveNaming.freeName("b.jpg") { it in taken })
        assertEquals("a_b_.pdf", SaveNaming.safe("a/b?.pdf"))
    }

    @Test
    fun localMessagesAndFailures() {
        assertFalse(media.canSave(msg(ChatAttachment.Photo(PhotoContent("p1", "u")), id = "local-1"), SaveTarget.GALLERY))
        saver.failure = RuntimeException()
        media.save(msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1"))), SaveTarget.GALLERY)
        assertEquals("Не удалось сохранить", (errors.single() as app.maxly.domain.MaxlyError.Rejected).text)
        assertTrue(media.state.value.saving.isEmpty())
    }

    @Test
    fun sharesTheItemOpenInTheViewer() {
        val m = msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1")), ChatAttachment.Video(VideoContent("v1", null)))
        media.openVisual(m, m.content.attachments[1])
        media.shareViewed()
        assertEquals(listOf("https://cdn/video-v1"), files.urls)
        assertEquals(ShareFile("/nonexistent/v1/video-v1.mp4", "Maxly 2026-10-01 14.05.33 2.mp4", SavedKind.VIDEO), media.state.value.shareFile)
        assertTrue(media.state.value.saving.isEmpty())
        media.consumeShareFile()
        assertEquals(null, media.state.value.shareFile)
    }

    @Test
    fun imageExtensionBySignature() {
        assertEquals("png", SaveNaming.imageExtension(byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 13, 10, 26, 10)))
        assertEquals("gif", SaveNaming.imageExtension("GIF89a".toByteArray()))
        assertEquals("webp", SaveNaming.imageExtension("RIFF\u0000\u0000\u0000\u0000WEBP".toByteArray()))
        assertEquals("jpg", SaveNaming.imageExtension(byteArrayOf(0xFF.toByte(), 0xD8.toByte())))
        assertEquals("Maxly 1970-01-01 00.00.00 3.png", SaveNaming.name(0, 2, "png", ZoneOffset.UTC))
    }

    private val avatarTime = java.time.LocalDateTime.of(2026, 10, 19, 15, 43, 0).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
    private val avatarMedia = ChatMedia("10", repo, TestScope(UnconfinedTestDispatcher()), null, files, saver, onNotice = { notices += it }, now = { avatarTime }) { errors += it }

    @Test
    fun savesTheAvatarOriginalToPictures() {
        avatarMedia.openAvatar("42", "https://cdn/a?r=1&fn=sqr_192", "Анна Смирнова", preview = "https://cdn/a?r=1&fn=sqr_288")
        assertTrue(avatarMedia.canSaveAvatar())
        avatarMedia.saveAvatar()
        assertEquals(listOf("https://cdn/a?r=1"), files.urls)
        assertEquals(listOf("Фото профиля — Анна Смирнова 2026-10-19 15.43.00.jpg"), saver.pictures)
        assertTrue(saver.saved.isEmpty())
        assertEquals(listOf("Фото сохранено"), notices)
        assertTrue(avatarMedia.state.value.saving.isEmpty())
    }

    @Test
    fun noAvatarNoViewerNoSave() {
        avatarMedia.openAvatar("42", null, "Анна")
        assertEquals(null, avatarMedia.state.value.viewer)
        assertFalse(avatarMedia.canSaveAvatar())
        avatarMedia.saveAvatar()
        assertTrue(files.urls.isEmpty() && saver.pictures.isEmpty() && notices.isEmpty())
    }

    @Test
    fun messageViewerIsNotSavedAsAvatar() {
        val m = msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1")))
        avatarMedia.openVisual(m, m.content.attachments.first())
        assertFalse(avatarMedia.canSaveAvatar())
        avatarMedia.saveAvatar()
        assertTrue(saver.pictures.isEmpty())
    }

    @Test
    fun avatarSaveFailureIsReported() {
        saver.failure = app.maxly.domain.MaxlyError.Rejected("Нет доступа к памяти телефона")
        avatarMedia.openAvatar("42", "https://cdn/a", "Анна")
        avatarMedia.saveAvatar()
        assertEquals(listOf("Нет доступа к памяти телефона"), errors.map { it.message })
        assertTrue(notices.isEmpty())
        assertTrue(avatarMedia.state.value.saving.isEmpty())
    }
}
