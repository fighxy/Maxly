package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.domain.Message
import app.orbitle.domain.Sticker
import app.orbitle.presentation.stickers.MemoryRecents
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private class MemoryDrafts : DraftStore {
    val map = mutableMapOf<String, String>()
    override fun get(chatId: String) = map[chatId]
    override fun put(chatId: String, text: String) {
        if (text.isBlank()) map.remove(chatId) else map[chatId] = text
    }
}

class DraftsTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val drafts = MemoryDrafts()

    @Test
    fun draftIsRestoredAndClearedOnSend() {
        drafts.map["10"] = "недописанное"
        val vm = ChatViewModel("10", repo, drafts = drafts)
        assertEquals("недописанное", vm.state.value.draft)
        vm.setDraft("готово")
        assertEquals("готово", drafts.map["10"])
        vm.send()
        assertNull(drafts.map["10"])
    }

    @Test
    fun editingDoesNotOverwriteDraft() {
        repo.list.value = listOf(Message("5", "10", "1", "старый", 1))
        val vm = ChatViewModel("10", repo, drafts = drafts)
        vm.setDraft("черновик")
        vm.beginEdit(repo.list.value.first())
        vm.setDraft("новый текст")
        assertEquals("черновик", drafts.map["10"])
        vm.cancelEdit()
        assertEquals("черновик", vm.state.value.draft)
    }

    @Test
    fun stickerGoesWithReplyAndIntoRecents() {
        val recents = MemoryRecents()
        val sent = mutableListOf<Pair<String, String?>>()
        val repo = object : app.orbitle.data.MessageRepository by repo {
            override suspend fun sendSticker(chatId: String, sticker: Sticker, replyTo: String?) {
                sent += sticker.id to replyTo
            }
        }
        val vm = ChatViewModel("10", repo, stickerRecents = recents)
        this.repo.list.value = listOf(Message("7", "10", "2", "т", 1))
        vm.beginReply(this.repo.list.value.first())
        vm.sendSticker(Sticker("42", "u"))
        assertEquals(listOf("42" to "7"), sent)
        assertNull(vm.state.value.replyTo)
        assertTrue(recents.recentStickers.any { it.id == "42" })
    }
}
