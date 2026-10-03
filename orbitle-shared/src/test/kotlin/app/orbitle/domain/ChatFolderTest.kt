package app.orbitle.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatFolderTest {
    private fun chat(id: String, type: ChatType = ChatType.PRIVATE, unread: Int = 0, muted: Boolean = false, bot: Boolean = false, pin: Int? = null, at: Long = 0) =
        Chat(id = id, title = id, type = type, unreadCount = unread, updatedAtMs = at, isMuted = muted, isBot = bot, pinOrder = pin)

    @Test
    fun codesFromNumbersAndNames() {
        assertEquals(ChatFolderRules.Code.DIALOG, ChatFolderRules.Code.fromText("4"))
        assertEquals(ChatFolderRules.Code.GROUP, ChatFolderRules.Code.fromText("CHAT"))
        assertEquals(ChatFolderRules.Code.BOT, ChatFolderRules.Code.fromText(" bot "))
        assertEquals(null, ChatFolderRules.Code.fromText("99"))
    }

    @Test
    fun typesAreOredAndStatesAnded() {
        val rules = ChatFolderRules(filters = listOf("2", "3", "0"))
        assertTrue(rules.matches(chat("1", ChatType.CHANNEL, unread = 1)))
        assertTrue(rules.matches(chat("2", ChatType.GROUP, unread = 1)))
        assertFalse(rules.matches(chat("3", ChatType.GROUP)))
        assertFalse(rules.matches(chat("4", ChatType.PRIVATE, unread = 1)))
    }

    @Test
    fun explicitChatsAlwaysMatch() {
        val rules = ChatFolderRules(chatIds = setOf("9"), filters = listOf("CHANNEL"))
        assertTrue(rules.matches(chat("9", ChatType.PRIVATE)))
        assertFalse(ChatFolderRules().matches(chat("1")))
    }

    @Test
    fun dialogsExcludeBotsAndSaved() {
        val rules = ChatFolderRules(filters = listOf("DIALOG"))
        assertTrue(rules.matches(chat("5")))
        assertFalse(rules.matches(chat("6", bot = true)))
        assertFalse(rules.matches(chat(Chat.SAVED_MESSAGES_ID)))
        assertTrue(ChatFolderRules(filters = listOf("10")).matches(chat("6", bot = true)))
    }

    @Test
    fun mutedStates() {
        assertTrue(ChatFolderRules(filters = listOf("7")).matches(chat("1", muted = true)))
        assertFalse(ChatFolderRules(filters = listOf("11")).matches(chat("1", muted = true)))
    }

    @Test
    fun archiveNeverInFolders() {
        assertFalse(ChatFolder.all.contains(chat("1").copy(isArchived = true)))
    }

    @Test
    fun listOrderPinsThenActivity() {
        val chats = listOf(chat("a", at = 10), chat("b", pin = 1), chat("c", at = 30), chat("d", pin = 0), chat("e", at = 30))
        assertEquals(listOf("d", "b", "c", "e", "a"), chats.sortedWith(Chat.listOrder).map { it.id })
    }

    @Test
    fun freshDraftRaisesChat() {
        val plain = chat("a", at = 10)
        val drafted = chat("b", at = 5).copy(draft = ChatDraft("x", 20))
        assertEquals(listOf("b", "a"), listOf(plain, drafted).sortedWith(Chat.listOrder).map { it.id })
    }
}
