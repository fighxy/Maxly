package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.FileContent
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.VideoContent
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
        var failure: Exception? = null
        override suspend fun save(path: String, name: String, kind: SavedKind) {
            failure?.let { throw it }
            saved += name to kind
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

    private val repo = object : app.orbitle.data.MessageRepository by FakeMessages() {
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
        assertEquals(listOf("Orbitle 2026-10-01 14.05.33.jpg" to SavedKind.IMAGE, "Orbitle 2026-10-01 14.05.33 2.mp4" to SavedKind.VIDEO), saver.saved)
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
    fun localMessagesAndFailures() {
        assertFalse(media.canSave(msg(ChatAttachment.Photo(PhotoContent("p1", "u")), id = "local-1"), SaveTarget.GALLERY))
        saver.failure = RuntimeException()
        media.save(msg(ChatAttachment.Photo(PhotoContent("p1", "https://cdn/p1"))), SaveTarget.GALLERY)
        assertEquals("Не удалось сохранить", (errors.single() as app.orbitle.domain.OrbitleError.Rejected).text)
        assertTrue(media.state.value.saving.isEmpty())
    }

    @Test
    fun imageExtensionBySignature() {
        assertEquals("png", SaveNaming.imageExtension(byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 13, 10, 26, 10)))
        assertEquals("gif", SaveNaming.imageExtension("GIF89a".toByteArray()))
        assertEquals("webp", SaveNaming.imageExtension("RIFF\u0000\u0000\u0000\u0000WEBP".toByteArray()))
        assertEquals("jpg", SaveNaming.imageExtension(byteArrayOf(0xFF.toByte(), 0xD8.toByte())))
        assertEquals("Orbitle 1970-01-01 00.00.00 3.png", SaveNaming.name(0, 2, "png", ZoneOffset.UTC))
    }
}
