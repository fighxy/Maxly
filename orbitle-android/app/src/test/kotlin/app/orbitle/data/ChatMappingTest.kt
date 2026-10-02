package app.orbitle.data

import app.orbitle.domain.ChatType
import app.orbitle.domain.DeliveryState
import app.orbitle.domain.MessageMediaKind
import com.max.core.api.AccountConfig
import com.max.core.api.MaxUser
import com.max.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.max.core.api.Chat as CoreChat

class ChatMappingTest {
    private val me = 1L

    private fun user(id: Long, first: String, options: List<String> = emptyList(), url: String? = null) = MaxUser.from(
        mapOf("id" to id, "names" to listOf(mapOf("firstName" to first, "lastName" to "Тест")), "options" to options, "baseUrl" to url),
    )!!

    private fun dialog(
        id: Long = 10,
        peer: Long = 2,
        last: Map<String, Any?>? = mapOf("id" to 500L, "sender" to 2L, "text" to "Привет", "time" to 1_000L, "type" to "USER"),
        participants: Map<Any, Any> = mapOf(me to 0L, peer to 0L),
        extra: Map<String, Any?> = emptyMap(),
    ) = CoreChat.from(
        mapOf("id" to id, "type" to "DIALOG", "status" to "ACTIVE", "lastEventTime" to 2_000L, "participants" to participants, "lastMessage" to last, "newMessages" to 3) + extra,
    )!!

    private fun state(vararg chats: CoreChat, users: List<MaxUser> = listOf(user(2, "Анна", url = "https://i/2"))) =
        MaxState(me = me, chats = chats.associateBy { it.id }, users = users.associateBy { it.id })

    @Test
    fun dialogTakesPeerNameAndAvatar() {
        val chat = ChatMapping.chat(dialog(), state(dialog()), null, 0)
        assertEquals("10", chat.id)
        assertEquals("Анна Тест", chat.title)
        assertEquals("https://i/2", chat.avatarUrl)
        assertEquals(ChatType.PRIVATE, chat.type)
        assertEquals(2_000L, chat.updatedAtMs)
        assertEquals(3, chat.unreadCount)
        assertEquals("Привет", chat.preview)
        assertEquals("2", chat.peerId)
        assertFalse(chat.lastMessage!!.isOutgoing)
        assertNull(chat.lastMessage.delivery)
    }

    @Test
    fun ownMessageReadByPeerMark() {
        val own = mapOf("id" to 500L, "sender" to me, "text" to "Ок", "time" to 1_000L, "type" to "USER")
        val read = dialog(last = own, participants = mapOf(me to 0L, 2L to 5_000L))
        assertEquals(DeliveryState.READ, ChatMapping.chat(read, state(read), null, 0).lastMessage?.delivery)
        val unread = dialog(last = own, participants = mapOf(me to 0L, 2L to 100L))
        assertEquals(DeliveryState.SENT, ChatMapping.chat(unread, state(unread), null, 0).lastMessage?.delivery)
    }

    @Test
    fun attachmentKinds() {
        fun kind(attach: Map<String, Any?>) = ChatMapping.attachmentKind(listOf(attach))
        assertEquals(MessageMediaKind.PHOTO, kind(mapOf("_type" to "PHOTO")))
        assertEquals(MessageMediaKind.GIF, kind(mapOf("_type" to "PHOTO", "gif" to true)))
        assertEquals(MessageMediaKind.VIDEO_MESSAGE, kind(mapOf("_type" to "VIDEO", "videoType" to 1)))
        assertEquals(MessageMediaKind.VIDEO, kind(mapOf("_type" to "VIDEO")))
        assertEquals(MessageMediaKind.VOICE, kind(mapOf("_type" to "AUDIO")))
        assertEquals(MessageMediaKind.CALL, kind(mapOf("_type" to "CALL")))
        assertEquals(MessageMediaKind.GROUP_CALL, kind(mapOf("_type" to "CALL", "joinLink" to "https://max.ru/call/1")))
        assertNull(kind(mapOf("_type" to "CONTROL")))
        assertNull(ChatMapping.attachmentKind(emptyList<Any>()))
    }

    @Test
    fun photoPreviewHasThumbnail() {
        val last = mapOf("id" to 1L, "sender" to 2L, "text" to "", "time" to 1L, "type" to "USER", "attaches" to listOf(mapOf("_type" to "PHOTO", "baseUrl" to "https://p/1")))
        val chat = dialog(last = last)
        val mapped = ChatMapping.chat(chat, state(chat), null, 0)
        assertNull(mapped.preview)
        assertEquals(MessageMediaKind.PHOTO, mapped.lastMessage?.media)
        assertEquals("https://p/1", mapped.lastMessage?.thumbnailUrl)
    }

    @Test
    fun forwardedMessageUsesInnerTextAndAttaches() {
        val last = mapOf(
            "id" to 1L, "sender" to 2L, "text" to "", "time" to 1L, "type" to "USER",
            "link" to mapOf("type" to "FORWARD", "message" to mapOf("text" to "", "attaches" to listOf(mapOf("_type" to "AUDIO")))),
        )
        val chat = dialog(last = last)
        val mapped = ChatMapping.chat(chat, state(chat), null, 0)
        assertTrue(mapped.lastMessage!!.isForwarded)
        assertEquals(MessageMediaKind.VOICE, mapped.lastMessage.media)
    }

    @Test
    fun botsOfficialAndWriteRights() {
        val users = listOf(user(2, "Бот", listOf("BOT", "OFFICIAL")), user(3, "Служба", listOf("OFFICIAL")))
        val bot = dialog(id = 11, peer = 2)
        val service = dialog(id = 12, peer = 3)
        val s = state(bot, service, users = users)
        val mappedBot = ChatMapping.chat(bot, s, null, 0)
        assertTrue(mappedBot.isBot)
        assertTrue(mappedBot.isVerified)
        assertEquals(true, mappedBot.canWrite)
        assertEquals(false, ChatMapping.chat(service, s, null, 0).canWrite)
    }

    @Test
    fun channelRightsAndComments() {
        val channel = CoreChat.from(
            mapOf("id" to 20L, "type" to "CHANNEL", "title" to "Новости", "owner" to 9L, "admins" to listOf(me), "options" to mapOf("COMMENTS" to false)),
        )!!
        val mapped = ChatMapping.chat(channel, state(channel), null, 0)
        assertEquals(ChatType.CHANNEL, mapped.type)
        assertEquals(true, mapped.canWrite)
        assertEquals(false, mapped.commentsEnabled)
        val left = CoreChat.from(mapOf("id" to 21L, "type" to "CHAT", "title" to "Группа", "status" to "LEFT"))!!
        assertEquals(false, ChatMapping.chat(left, state(left), null, 0).canWrite)
    }

    @Test
    fun pinsAndMute() {
        val a = dialog(id = 10)
        val config = AccountConfig().withChatMute(10, -1)
        val chats = ChatMapping.chats(state(a), config, 0)
        assertTrue(chats.single().isMuted)
    }

    @Test
    fun foldersSkipNothingAndMarkAll() {
        val folders = com.max.core.api.ChatFolders(
            listOf(
                com.max.core.api.Folder.from(mapOf("id" to "all.chat.folder", "title" to "Все"))!!,
                com.max.core.api.Folder.from(mapOf("id" to "f1", "title" to "Работа", "include" to listOf(10L), "filters" to listOf(4L, "CHANNEL")))!!,
            ),
        )
        val mapped = ChatMapping.folders(folders)
        assertTrue(mapped[0].isAllChats)
        assertEquals(listOf("10"), mapped[1].chatIds)
        assertEquals(listOf("4", "CHANNEL"), mapped[1].filters)
    }
}
