package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.VideoContent
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class RoundAndUploadTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val round = VideoContent("r1", null, isRound = true)
    private val note = Message("7", "10", "2", "", 1_000L, content = MessageContent(attachments = listOf(ChatAttachment.Video(round))))

    @Test
    fun roundPlaysInlineAndStops() {
        val media = ChatMedia("10", repo, TestScope(UnconfinedTestDispatcher()), null, null) {}
        media.openVisual(note, ChatAttachment.Video(round))
        assertEquals(RoundPlayback("7", "r1", repo.link), media.state.value.round)
        assertNull(media.state.value.viewer)
        media.toggleRound(note, round)
        assertNull(media.state.value.round)
        media.toggleRound(note, round)
        media.stopRound("r1")
        assertNull(media.state.value.round)
    }

    @Test
    fun ordinaryVideoStillOpensViewer() {
        val media = ChatMedia("10", repo, TestScope(UnconfinedTestDispatcher()), null, null) {}
        val video = VideoContent("v1", null)
        media.openVisual(note.copy(content = MessageContent(attachments = listOf(ChatAttachment.Video(video)))), ChatAttachment.Video(video))
        assertNull(media.state.value.round)
        assertEquals("7", media.state.value.viewer?.messageId)
    }

    @Test
    fun cancelUploadRemovesSendingMediaMessages() {
        val sending = Message("local-3", "10", "1", "", 2_000L, status = MessageStatus.SENDING, content = MessageContent(attachments = listOf(ChatAttachment.Photo(PhotoContent("local-0", "file:///p")))))
        val text = Message("local-4", "10", "1", "т", 3_000L, status = MessageStatus.SENDING)
        repo.list.value = listOf(note, sending, text)
        val vm = ChatViewModel("10", repo, ChatFormatter(ZoneOffset.UTC), now = { 10_000L })
        assertTrue(vm.canCancelUpload(sending))
        assertFalse(vm.canCancelUpload(text))
        assertFalse(vm.canCancelUpload(note))
        vm.cancelUpload()
        assertEquals(listOf("7", "local-4"), repo.list.value.map { it.id })
    }
}
