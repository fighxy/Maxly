package app.orbitle.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ChatCreateTest {
    @Test
    fun channelPayloadIsControlNewWithChannelType() {
        val payload = CoreChatRepository.channelCreatePayload(15L, "Новости")
        assertEquals(true, payload["notify"])
        val message = payload["message"] as Map<*, *>
        assertEquals(15L, message["cid"])
        val attach = (message["attaches"] as List<*>).single() as Map<*, *>
        assertEquals("CONTROL", attach["_type"])
        assertEquals("new", attach["event"])
        assertEquals("CHANNEL", attach["chatType"])
        assertEquals("Новости", attach["title"])
        assertEquals(emptyList<Long>(), attach["userIds"])
    }

    @Test
    fun dialogPlaceholderKeepsPeerAndDoesNotInventAChat() {
        val chat = CoreChatRepository.dialogPlaceholder(1L xor 6L, 1L, 6L, "Маша")
        assertEquals(1L xor 6L, chat.id)
        assertEquals("DIALOG", chat.type)
        assertEquals("ACTIVE", chat.status)
        assertEquals("Маша", chat.title)
        assertEquals(setOf("1", "6"), (chat.raw["participants"] as Map<*, *>).keys)
        assertEquals(6L, ChatMapping.dialogPeer(chat, 1L))
    }
}
