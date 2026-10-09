package app.maxly.data

import app.maxly.domain.Chat
import com.max.core.api.AccountConfig
import com.max.core.api.AccountConfigUpdate
import com.max.core.state.MaxState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
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

    /** Полный снимок: `LOGIN` с хешем по умолчанию (`chatsKnown`). */
    private fun snapshot(vararg mutes: Pair<Long, Long>) =
        AccountConfig().replacedBy(AccountConfigUpdate(chats = mutes.associate { (id, until) -> id.toString() to mapOf("dontDisturbUntil" to until) }))

    /** Пуш `NOTIF_CONFIG` 134 о звуке одного чата, влитый в конфиг, как это делает ядро. */
    private fun AccountConfig.push(chatId: Long, until: Long) =
        mergedWith(AccountConfigUpdate.fromPush(mapOf("chats" to mapOf(chatId.toString() to mapOf("dontDisturbUntil" to until))))!!)

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
    fun incompleteConfigKeepsExistingMutes() {
        val mutes = ChatMutes()
        val s = state(10, 20)
        val full = snapshot(10L to -1L)
        assertTrue(ChatMapping.chats(s, full, 0, mutes).muted(10))
        assertFalse(ChatMapping.chats(s, full, 0, mutes).muted(20))
        // `LOGIN` после переподключения без `chats`: ядро сливает, звук не меняется.
        val merged = full.mergedWith(AccountConfigUpdate(hash = "h2"))
        assertTrue(ChatMapping.chats(s, merged, 0, mutes).muted(10))
        // Конфиг, который о чатах не знает вовсе (`chatsKnown` false): по памяти.
        val partial = AccountConfig(hash = "h3")
        assertTrue(ChatMapping.chats(s, partial, 0, mutes).muted(10))
        assertFalse(ChatMapping.chats(s, partial, 0, mutes).muted(20))
    }

    @Test
    fun fullSnapshotWithoutEntryIsSoundOnDespiteMemory() {
        val mutes = ChatMutes()
        assertTrue(mutes.isMuted(10, config(10L to -1L), 0))
        // Полный `chats` не называет чаты со звуком: значит, звук включён.
        assertFalse(mutes.isMuted(10, snapshot(20L to -1L), 0))
        assertFalse(mutes.isMuted(10, null, 0))
    }

    @Test
    fun dontDisturbZeroTurnsTheSoundOn() {
        val mutes = ChatMutes()
        val muted = snapshot(10L to -1L)
        assertTrue(mutes.isMuted(10, muted, 0))
        val unmuted = muted.push(10, 0)
        assertFalse(mutes.isMuted(10, unmuted, 0))
        // И память теперь «со звуком».
        assertFalse(mutes.isMuted(10, AccountConfig(), 0))
    }

    @Test
    fun configPushChangesOnlyItsChat() = runTest {
        val config = MutableStateFlow<AccountConfig?>(snapshot(10L to -1L))
        val seen = mutableListOf<List<Chat>?>()
        val job = launch {
            ChatMutes.chatList(MutableStateFlow(state(10, 20, 30)), config, MutableStateFlow(true), ChatMutes(), { 0L }).collect { seen += it }
        }
        runCurrent()
        assertEquals(listOf(true, false, false), listOf(10L, 20L, 30L).map { seen.last().muted(it) })
        config.value = config.value!!.push(20, -1)
        runCurrent()
        assertEquals(listOf(true, true, false), listOf(10L, 20L, 30L).map { seen.last().muted(it) })
        config.value = config.value!!.push(10, 0)
        runCurrent()
        assertEquals(listOf(false, true, false), listOf(10L, 20L, 30L).map { seen.last().muted(it) })
        job.cancel()
    }

    @Test
    fun pushedTimedMuteExpiresByItsEnd() = runTest {
        val base = 1_000_000L
        val clock = { base + testScheduler.currentTime }
        val config = MutableStateFlow<AccountConfig?>(snapshot())
        val seen = mutableListOf<List<Chat>?>()
        val job = launch {
            ChatMutes.chatList(MutableStateFlow(state(10)), config, MutableStateFlow(true), ChatMutes(), clock).collect { seen += it }
        }
        runCurrent()
        assertFalse(seen.last().muted(10))
        config.value = config.value!!.push(10, base + 30_000)
        runCurrent()
        assertTrue(seen.last().muted(10))
        // Конец выключенного звука ядро не присылает: список пересобирается сам.
        advanceTimeBy(31_000)
        runCurrent()
        assertFalse(seen.last().muted(10))
        job.cancel()
    }

    @Test
    fun configPushSignalRereadsTheList() = runTest {
        var now = 1_000_000L
        val pushes = MutableSharedFlow<Unit>()
        val config = MutableStateFlow<AccountConfig?>(snapshot(10L to now + 60_000))
        val seen = mutableListOf<List<Chat>?>()
        val job = launch {
            ChatMutes.chatList(MutableStateFlow(state(10)), config, MutableStateFlow(true), ChatMutes(), { now }, pushes).collect { seen += it }
        }
        runCurrent()
        assertTrue(seen.last().muted(10))
        // Часы ушли дальше конца, таймер ещё не сработал: пуш перечитывает список.
        now += 120_000
        pushes.emit(Unit)
        runCurrent()
        assertFalse(seen.last().muted(10))
        job.cancel()
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
