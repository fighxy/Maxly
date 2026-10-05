package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.HistorySpan
import app.orbitle.data.MessageRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

/** Сервер с историей [server]: страницы назад, вперёд и вокруг момента, как у ядра. */
private class PagedMessages(val base: FakeMessages = FakeMessages()) : MessageRepository by base {
    var server: List<Message> = emptyList()
    val around = mutableListOf<Long>()
    val older = mutableListOf<Long>()
    val newer = mutableListOf<Long>()

    private fun store(page: List<Message>) {
        base.list.value = (base.list.value + page).distinctBy { it.id }.sortedBy { it.timeMs }
    }

    private fun span(page: List<Message>, oldest: Boolean, newest: Boolean): HistorySpan? =
        if (page.isEmpty()) null else HistorySpan(page.first().timeMs, page.last().timeMs, page.size, oldest, newest)

    override suspend fun openLatestPage(chatId: String): HistorySpan? {
        val page = server.takeLast(40)
        store(page)
        return span(page, oldest = page.size == server.size, newest = true)
    }

    override suspend fun olderPage(chatId: String, beforeMs: Long): HistorySpan? {
        older += beforeMs
        val all = server.filter { it.timeMs < beforeMs }
        val page = all.takeLast(40)
        store(page)
        return span(page, oldest = page.size == all.size, newest = false) ?: HistorySpan.START
    }

    override suspend fun newerPage(chatId: String, afterMs: Long): HistorySpan? {
        newer += afterMs
        val page = server.filter { it.timeMs > afterMs }.take(40)
        store(page)
        return span(page, oldest = false, newest = page.isEmpty() || page.last() == server.last())
            ?: HistorySpan(afterMs, afterMs, 0, reachedNewest = true)
    }

    override suspend fun pageAround(chatId: String, timeMs: Long): HistorySpan? {
        around += timeMs
        val before = server.filter { it.timeMs < timeMs }.takeLast(15)
        val after = server.filter { it.timeMs >= timeMs }.take(30)
        val page = before + after
        store(page)
        return span(page, oldest = before.size < 15, newest = after.lastOrNull() == server.last())
    }

    override suspend fun findMessage(chatId: String, messageId: String): Message? = server.firstOrNull { it.id == messageId }
}

class ChatTimelineTest {
    @get:Rule val main = MainDispatcherRule()

    private val now = 1_790_683_200_000L
    private val start = now - 200 * 60_000L
    private val repo = PagedMessages()

    /** Сообщение №[n]: раз в минуту, чужие. */
    private fun msg(n: Int, author: String = "2") =
        Message(id = "$n", chatId = "10", authorId = author, text = "т$n", timeMs = start + n * 60_000L, authorName = "Анна")

    private fun time(n: Int) = start + n * 60_000L

    private fun chat(unread: Int) = Chat(id = "10", title = "Анна", type = ChatType.PRIVATE, updatedAtMs = now, unreadCount = unread)

    private fun vm() = ChatViewModel("10", repo, ChatFormatter(ZoneOffset.UTC), now = { now })

    private fun keys(model: ChatViewModel) = model.state.value.items.filterIsInstance<ChatItem.Bubble>().map { it.key.toInt() }

    @Before
    @After
    fun forget() {
        HistoryRanges.clear()
        ScrollMemory.clear()
    }

    @Test
    fun opensAtTheFirstUnreadFarBackAndGrowsToTheLatest() {
        repo.server = (1..199).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 99), readMarkMs = time(100))
        val model = vm()
        val state = model.state.value
        // Свежая страница — с №160: отметка раньше, окно грузится вокруг неё.
        assertEquals(listOf(time(100)), repo.around)
        assertEquals(ScrollRequest.Target.Unread("101"), state.scroll?.target)
        assertTrue(state.hasNewer)
        val shown = keys(model)
        assertEquals(85, shown.min())
        assertEquals(129, shown.max())
        val divider = state.items.indexOfFirst { it is ChatItem.Unread }
        assertEquals("101", state.items[divider - 1].key)
        // Ничего не прочитано, пока экран не показал сообщения.
        assertTrue(repo.base.reads.isEmpty())
        model.onVisible("110", atBottom = false)
        assertEquals(listOf("110"), repo.base.reads)
        model.loadNewer()
        // Страница вперёд перекрыла свежую: дальше это обычная лента.
        assertFalse(model.state.value.hasNewer)
        assertEquals(199, keys(model).max())
        assertEquals(85, keys(model).min())
    }

    @Test
    fun unreadInsideTheLatestPageNeedsNoWindow() {
        repo.server = (1..199).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 9), readMarkMs = time(190))
        val model = vm()
        assertTrue(repo.around.isEmpty())
        assertEquals(ScrollRequest.Target.Unread("191"), model.state.value.scroll?.target)
        assertFalse(model.state.value.hasNewer)
        assertEquals(9, model.state.value.unreadBelow)
    }

    @Test
    fun returnsToTheSavedPlaceWithoutUnread() {
        repo.server = (1..199).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        ScrollMemory.put("10", ScrollPlace("170", 24))
        val model = vm()
        assertEquals(ScrollRequest.Target.Place(ScrollPlace("170", 24)), model.state.value.scroll?.target)
        val token = model.state.value.scroll!!.token
        model.consumeScroll(token)
        assertNull(model.state.value.scroll)
        model.savePlace(null)
        assertNull(ScrollMemory.get("10"))
    }

    @Test
    fun jumpsToAFarReplyAndComesBack() {
        repo.server = (1..199).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        val model = vm()
        model.jumpTo("20", from = "199")
        var state = model.state.value
        assertEquals(listOf(time(20)), repo.around)
        assertEquals(ScrollRequest.Target.Message("20", highlight = true), state.scroll?.target)
        assertTrue(state.hasNewer)
        assertTrue(state.canReturn)
        assertTrue(20 in keys(model) && 199 !in keys(model))
        // «Вниз»: сначала туда, откуда пришли — это живая лента.
        model.scrollDown()
        state = model.state.value
        assertEquals(ScrollRequest.Target.Message("199", highlight = false), state.scroll?.target)
        assertFalse(state.hasNewer)
        assertFalse(state.canReturn)
        assertTrue(199 in keys(model))
        model.scrollDown()
        assertEquals(ScrollRequest.Target.Bottom, model.state.value.scroll?.target)
    }

    @Test
    fun jumpToALoadedMessageOnlyScrolls() {
        repo.server = (1..199).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        val model = vm()
        model.jumpTo("190")
        assertTrue(repo.around.isEmpty())
        assertEquals(ScrollRequest.Target.Message("190", highlight = true), model.state.value.scroll?.target)
        assertFalse(model.state.value.canReturn)
    }

    @Test
    fun sendingFromAJumpWindowGoesBackToTheLatest() {
        repo.server = (1..199).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        val model = vm()
        model.jumpTo("20", from = "199")
        model.setDraft("привет")
        model.send()
        val state = model.state.value
        assertFalse(state.hasNewer)
        assertFalse(state.canReturn)
        assertEquals(ScrollRequest.Target.Bottom, state.scroll?.target)
        assertTrue(199 in keys(model))
    }

    @Test
    fun olderPagesContinueFromTheOldestShownAndStopAtTheBeginning() {
        repo.server = (1..100).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        val model = vm()
        assertEquals(61, keys(model).min())
        model.loadOlder()
        assertEquals(listOf(time(61)), repo.older)
        assertEquals(21, keys(model).min())
        assertTrue(model.state.value.hasOlder)
        model.loadOlder()
        assertEquals(1, keys(model).min())
        assertFalse(model.state.value.hasOlder)
    }

    @Test
    fun theDownButtonCountsWhatArrivedBelow() {
        repo.server = (1..100).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        val model = vm()
        model.onVisible("90", atBottom = false)
        assertEquals(10, model.state.value.unreadBelow)
        repo.base.list.value = repo.base.list.value + msg(101) + msg(102, author = "1")
        assertEquals(11, model.state.value.unreadBelow)
        model.onVisible("102", atBottom = true)
        assertEquals(0, model.state.value.unreadBelow)
    }

    @Test
    fun aMissingMessageIsReported() {
        repo.server = (1..50).map(::msg)
        repo.base.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        val model = vm()
        model.jumpTo("999", from = "50")
        assertEquals("Сообщение не найдено", model.messages.value)
        assertFalse(model.state.value.canReturn)
    }
}
