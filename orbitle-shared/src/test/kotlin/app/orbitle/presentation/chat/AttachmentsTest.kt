package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.domain.Message
import app.orbitle.domain.OutgoingFile
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AttachmentsTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private fun file(n: Int, kind: OutgoingFile.Kind = OutgoingFile.Kind.PHOTO) = OutgoingFile("/cache/$n.jpg", "$n.jpg", kind, 100)

    @Test
    fun kindFollowsMime() {
        assertEquals(OutgoingFile.Kind.PHOTO, OutgoingFile.kindOf("image/jpeg"))
        assertEquals(OutgoingFile.Kind.VIDEO, OutgoingFile.kindOf("video/mp4"))
        assertEquals(OutgoingFile.Kind.FILE, OutgoingFile.kindOf("image/svg+xml"))
        assertEquals(OutgoingFile.Kind.FILE, OutgoingFile.kindOf("application/pdf"))
        assertEquals(OutgoingFile.Kind.FILE, OutgoingFile.kindOf(null))
    }

    @Test
    fun attachmentsAloneCanBeSent() {
        val vm = ChatViewModel("10", repo)
        assertFalse(vm.state.value.canSend)
        vm.addAttachments(listOf(file(1)))
        assertTrue(vm.state.value.canSend)
    }

    @Test
    fun duplicatesAreSkippedAndLimitApplies() {
        val vm = ChatViewModel("10", repo)
        vm.addAttachments(listOf(file(1), file(1)))
        assertEquals(1, vm.state.value.attachments.size)
        vm.addAttachments((2..12).map { file(it) })
        assertEquals(OutgoingFile.LIMIT, vm.state.value.attachments.size)
        assertTrue(vm.messages.value!!.contains("10"))
    }

    @Test
    fun sendUsesDraftAsCaptionAndReply() {
        val vm = ChatViewModel("10", repo)
        repo.list.value = listOf(Message("7", "10", "2", "т", 1))
        vm.beginReply(repo.list.value.first())
        vm.addAttachments(listOf(file(1), file(2, OutgoingFile.Kind.FILE)))
        vm.setDraft("  подпись ")
        repo.mediaGate = CompletableDeferred()
        vm.send()
        val (items, caption, reply) = repo.media.single()
        assertEquals(2, items.size)
        assertEquals("подпись", caption)
        assertEquals("7", reply)
        assertEquals(0.4f, vm.state.value.uploadProgress)
        assertTrue(vm.state.value.attachments.isEmpty())
        assertEquals("", vm.state.value.draft)
        assertNull(vm.state.value.replyTo)
        repo.mediaGate!!.complete(Unit)
        assertNull(vm.state.value.uploadProgress)
    }

    @Test
    fun removeDropsOneAttachment() {
        val vm = ChatViewModel("10", repo)
        vm.addAttachments(listOf(file(1), file(2)))
        vm.removeAttachment(file(1))
        assertEquals(listOf("/cache/2.jpg"), vm.state.value.attachments.map { it.path })
    }
}
