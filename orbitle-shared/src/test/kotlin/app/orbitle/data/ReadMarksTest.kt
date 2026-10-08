package app.orbitle.data

import com.max.core.api.MaxMessage
import com.max.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import com.max.core.api.Chat as CoreChat

class ReadMarksTest {
    private val me = 1L
    private val peer = 2L

    private fun message(id: Long, time: Long, sender: Long = peer) =
        MaxMessage.from(mapOf("id" to id, "sender" to sender, "text" to "т$id", "time" to time, "type" to "USER"), 10L)!!

    private fun chat(
        type: String = "DIALOG",
        participants: Map<Any, Any> = mapOf(me to 0L, peer to 0L),
        last: MaxMessage? = message(500, 1_000),
        unread: Int = 3,
    ) = CoreChat.from(
        mapOf(
            "id" to 10L, "type" to type, "status" to "ACTIVE", "lastEventTime" to 2_000L, "participants" to participants, "newMessages" to unread,
            "lastMessage" to last?.let { mapOf("id" to it.id, "sender" to it.sender, "text" to it.text, "time" to it.time, "type" to "USER") },
        ),
    )!!

    private fun state(chat: CoreChat, marks: Map<Long, Long> = emptyMap(), messages: List<MaxMessage> = emptyList()) =
        MaxState(me = me, chats = mapOf(chat.id to chat), messages = mapOf(chat.id to messages), readMarks = mapOf(chat.id to marks))

    @Test
    fun peerMarkTakesTheNewerOfCardAndPush() {
        val card = chat(participants = mapOf(me to 0L, peer to 1_500L))
        assertEquals(1_500L, ReadMarks.peer(card, state(card)))
        // Пуш прочтения карточку не меняет: отметка из пуша новее.
        assertEquals(3_000L, ReadMarks.peer(card, state(card, marks = mapOf(peer to 3_000L))))
        // Своя отметка — не собеседника.
        assertEquals(1_500L, ReadMarks.peer(card, state(card, marks = mapOf(me to 9_000L))))
        val channel = chat(type = "CHANNEL", participants = mapOf(peer to 5_000L))
        assertEquals(0L, ReadMarks.peer(channel, state(channel, marks = mapOf(peer to 6_000L))))
    }

    @Test
    fun ownMarkTakesTheNewerOfCardAndPush() {
        val card = chat(participants = mapOf(me to 1_200L, peer to 0L))
        assertEquals(1_200L, ReadMarks.own(card, state(card)))
        assertEquals(4_000L, ReadMarks.own(card, state(card, marks = mapOf(me to 4_000L, peer to 9_000L))))
    }

    @Test
    fun markIsTheMessageServerTime() {
        val stored = message(400, 900)
        val card = chat(last = message(500, 1_000))
        val st = state(card, messages = listOf(stored))
        assertEquals(900L, ReadMarks.messageTime(st, 10L, 400L))
        // Последнее сообщение чата есть в карточке, даже если истории не загружено.
        assertEquals(1_000L, ReadMarks.messageTime(st, 10L, 500L))
        assertNull(ReadMarks.messageTime(st, 10L, 999L))
    }
}
