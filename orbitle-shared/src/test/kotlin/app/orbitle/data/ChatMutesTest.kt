package app.orbitle.data

import app.orbitle.domain.Chat
import com.max.core.api.AccountConfig
import com.max.core.state.MaxState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.max.core.api.Chat as CoreChat

@OptIn(ExperimentalCoroutinesApi::class)
class ChatMutesTest {
    private fun group(id: Long) = CoreChat.from(mapOf("id" to id, "type" to "CHAT", "status" to "ACTIVE", "title" to "Группа $id"))!!

    private fun state(vararg ids: Long) = MaxState(me = 1, chats = ids.map(::group).associateBy { it.id })

    private fun config(vararg mutes: Pair<Long, Long>) =
        AccountConfig(chats = mutes.associate { (id, until) -> id.toString() to mapOf("dontDisturbUntil" to until) })

    private fun List<Chat>?.muted(id: Long): Boolean = this!!.single { it.id == id.toString() }.isMuted

    @Test
    fun configWithoutChatsKeepsKnownMutes() {
        val mutes = ChatMutes()
        val s = state(10, 20)
        assertTrue(ChatMapping.chats(s, config(10L to -1L, 20L to 0L), 0, mutes).muted(10))
        // Новый конфиг без `chats`: звук не включается сам.
        val next = ChatMapping.chats(s, AccountConfig(hash = "h2"), 0, mutes)
        assertTrue(next.muted(10))
        assertFalse(next.muted(20))
    }

    @Test
    fun unknownKeepsLastValueAndNeverKnownIsSoundOn() {
        val mutes = ChatMutes()
        assertTrue(mutes.isMuted(10, config(10L to -1L), 0))
        assertTrue(mutes.isMuted(10, null, 0))
        assertTrue(mutes.isMuted(10, config(30L to -1L), 0))
        assertFalse(mutes.isMuted(20, null, 0))
        // Явное «со звуком» перекрывает память.
        assertFalse(mutes.isMuted(10, config(10L to 0L), 0))
        assertFalse(mutes.isMuted(10, null, 0))
        mutes.clear()
        assertFalse(ChatMutes().isMuted(10, null, 0))
    }

    @Test
    fun rememberedTimedMuteStillExpires() {
        val mutes = ChatMutes()
        assertTrue(mutes.isMuted(10, config(10L to 1_000L), 500))
        assertTrue(mutes.isMuted(10, AccountConfig(), 999))
        assertFalse(mutes.isMuted(10, AccountConfig(), 1_000))
        assertEquals(1_000L, mutes.nextExpiry(listOf(10L), null, 500))
        assertNull(mutes.nextExpiry(listOf(10L), null, 1_000))
    }

    @Test
    fun withoutMemoryMappingStaysAsBefore() {
        assertTrue(ChatMapping.chats(state(10), config(10L to -1L), 0).muted(10))
        assertFalse(ChatMapping.chats(state(10), null, 0).muted(10))
    }

    @Test
    fun listDropsTimedMuteWhenItExpires() = runTest {
        val base = 1_000_000L
        val clock = { base + testScheduler.currentTime }
        val config = MutableStateFlow<AccountConfig?>(config(10L to base + 60_000, 20L to -1L))
        val seen = mutableListOf<List<Chat>?>()
        val job = launch {
            ChatMutes.chatList(MutableStateFlow(state(10, 20)), config, MutableStateFlow(true), ChatMutes(), clock).collect { seen += it }
        }
        runCurrent()
        assertTrue(seen.last().muted(10))
        advanceTimeBy(59_000)
        runCurrent()
        assertTrue(seen.last().muted(10))
        advanceTimeBy(2_000)
        runCurrent()
        assertFalse(seen.last().muted(10))
        assertTrue(seen.last().muted(20))
        job.cancel()
    }

    @Test
    fun configChangeAloneRebuildsTheList() = runTest {
        val config = MutableStateFlow<AccountConfig?>(config(10L to 0L))
        val states = MutableStateFlow(state(10))
        val seen = mutableListOf<List<Chat>?>()
        val job = launch {
            ChatMutes.chatList(states, config, MutableStateFlow(true), ChatMutes(), { 0L }).collect { seen += it }
        }
        runCurrent()
        assertFalse(seen.last().muted(10))
        config.value = config(10L to -1L)
        runCurrent()
        assertTrue(seen.last().muted(10))
        assertEquals(2, seen.size)
        job.cancel()
    }

    @Test
    fun noSnapshotYetIsNull() = runTest {
        val seen = mutableListOf<List<Chat>?>()
        val job = launch {
            ChatMutes.chatList(MutableStateFlow(MaxState()), MutableStateFlow(null), MutableStateFlow(false), ChatMutes(), { 0L }).collect { seen += it }
        }
        runCurrent()
        assertEquals(listOf<List<Chat>?>(null), seen)
        job.cancel()
    }
}
