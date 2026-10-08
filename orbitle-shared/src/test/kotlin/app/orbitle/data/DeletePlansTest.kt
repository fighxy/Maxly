package app.orbitle.data

import app.orbitle.domain.DeleteScope
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Права на удаление чужого и неотправленное — по правилам ядра, план собирает [DeletePlans]. */
class DeletePlansTest {
    private val now = 1_800_000_000_000L
    private fun msg(id: String, author: String = "2", at: Long = now - 60_000, status: MessageStatus = MessageStatus.SENT) =
        Message(id = id, chatId = "-10", authorId = author, text = "т", timeMs = at, status = status)

    private fun plan(type: String, messages: List<Message>, permissions: Long? = null, owner: Boolean = false, timeout: Long = 86_400) =
        DeleteStore.plan("1", if (type == "CHANNEL") "-20" else "-10", type, admin = false, messages = messages, editTimeoutSeconds = timeout, nowMs = now, permissions = permissions, owner = owner)

    @Test
    fun groupAdminNeedsTheEditDeleteBit() {
        assertEquals(DeleteScope.ALL, plan("CHAT", listOf(msg("5")), permissions = 1).scopes["5"])
        // Бит 1024 удаляет чужое только в канале.
        assertEquals(DeleteScope.SELF, plan("CHAT", listOf(msg("5")), permissions = 1024).scopes["5"])
        assertEquals(DeleteScope.SELF, plan("CHAT", listOf(msg("5")), permissions = 0).scopes["5"])
        assertEquals(DeleteScope.ALL, plan("CHAT", listOf(msg("5")), owner = true).scopes["5"])
    }

    @Test
    fun channelAdminDeletesWithEitherBitAndOnlyForEveryone() {
        for (bits in listOf(1024L, 1L)) {
            val p = plan("CHANNEL", listOf(msg("5")), permissions = bits)
            assertEquals(DeleteScope.ALL, p.scopes["5"])
            assertTrue(p.forcesForEveryone)
            assertFalse(p.showsForEveryone)
        }
        val subscriber = plan("CHANNEL", listOf(msg("5")), permissions = 0)
        assertEquals(DeleteScope.NONE, subscriber.scopes["5"])
        assertFalse(subscriber.canDelete)
    }

    @Test
    fun ownMessageIsFreshOnlyStrictlyInsideTheEditTimeout() {
        assertEquals(DeleteScope.ALL, plan("CHAT", listOf(msg("5", author = "1", at = now - 59_999)), timeout = 60).scopes["5"])
        assertEquals(DeleteScope.SELF, plan("CHAT", listOf(msg("5", author = "1", at = now - 60_000)), timeout = 60).scopes["5"])
        assertEquals(DeleteScope.SELF, plan("CHAT", listOf(msg("5", author = "1")), timeout = 0).scopes["5"])
    }

    @Test
    fun unsentMessagesStayLocal() {
        val pending = msg("local-1", author = "1", status = MessageStatus.SENDING)
        assertEquals(DeleteScope.SELF, plan("CHAT", listOf(pending)).scopes["local-1"])
        assertEquals(DeleteScope.NONE, plan("CHANNEL", listOf(pending)).scopes["local-1"])
        assertEquals(DeleteScope.SELF, plan("CHANNEL", listOf(pending), permissions = 1024).scopes["local-1"])
        // Вместе с ушедшим своим свежим: «у всех» не предлагается.
        val mixed = plan("CHAT", listOf(msg("5", author = "1"), pending))
        assertEquals(listOf("5", "local-1"), mixed.scopes.keys.toList())
        assertFalse(mixed.showsForEveryone)
        assertTrue(mixed.canDelete)
    }
}
