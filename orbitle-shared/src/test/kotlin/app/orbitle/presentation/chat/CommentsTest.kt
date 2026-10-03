package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.CommentsRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class FakeComments : CommentsRepository {
    val all = (1..45).map { Message("${100 + it}", "10", "${it % 3 + 2}", "к$it", 1_000L * it, authorName = "Автор") }
    var failure: Exception? = null
    var sendFailure: Exception? = null
    var reactionFailure: Exception? = null
    val asked = mutableListOf<List<String>>()
    val sent = mutableListOf<String>()
    var countsReply: Map<String, Int> = emptyMap()
    override suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message> {
        failure?.let { throw it }
        return all.filter { beforeMs == null || it.timeMs < beforeMs }.takeLast(limit)
    }
    override suspend fun send(text: String, chatId: String, postId: String): Message {
        sendFailure?.let { throw it }
        sent += text
        return Message("900", chatId, "1", text, 99_000L)
    }
    override suspend fun counts(chatId: String, postIds: List<String>): Map<String, Int> {
        asked += postIds
        return countsReply
    }
    override suspend fun setReaction(chatId: String, postId: String, commentId: String, emoji: String?): List<MessageReaction>? {
        reactionFailure?.let { throw it }
        return null
    }
}

class CommentsTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeComments()
    private val post = Message("9", "10", "0", "Пост", 500L, content = MessageContent(comments = 45))
    private val model by lazy {
        CommentsModel("10", post, "1", repo, CoroutineScope(UnconfinedTestDispatcher()), ChatFormatter(ZoneOffset.UTC), now = { 100_000L })
    }

    @Test
    fun loadsNewestPageThenOlder() {
        assertEquals("45 комментариев", model.title())
        model.load()
        val state = model.state.value
        assertEquals(CommentsState.Phase.Loaded, state.phase)
        assertEquals(30, state.comments.size)
        assertEquals("к16", state.comments.first().text)
        assertTrue(state.hasMore)
        assertEquals("45 комментариев", model.title())
        model.loadOlder()
        assertEquals(45, model.state.value.comments.size)
        assertEquals(false, model.state.value.hasMore)
        assertEquals("к1", model.state.value.comments.first().text)
    }

    @Test
    fun failedFirstLoadOffersRetry() {
        repo.failure = OrbitleError.Rejected("нет")
        model.load()
        assertEquals(CommentsState.Phase.Failed("нет"), model.state.value.phase)
        repo.failure = null
        model.reload()
        assertEquals(CommentsState.Phase.Loaded, model.state.value.phase)
    }

    @Test
    fun sendReplacesLocalWithServerCopy() {
        model.load()
        model.setDraft("  привет ")
        model.send()
        val last = model.state.value.comments.last()
        assertEquals("900", last.id)
        assertEquals("привет", last.text)
        assertEquals("", model.state.value.draft)
        assertEquals(listOf("привет"), repo.sent)
    }

    @Test
    fun failedSendKeepsTextAndCanRetry() {
        model.load()
        repo.sendFailure = OrbitleError.Rejected("нельзя")
        model.setDraft("привет")
        model.send()
        val failed = model.state.value.comments.last()
        assertEquals(MessageStatus.FAILED, failed.status)
        assertEquals("привет", model.state.value.draft)
        assertEquals("нельзя", model.state.value.error)
        repo.sendFailure = null
        model.retry(failed.id)
        assertEquals("900", model.state.value.comments.last().id)
        assertTrue(model.state.value.comments.none { it.status == MessageStatus.FAILED })
    }

    @Test
    fun reactionRollsBackOnFailure() {
        model.load()
        val comment = model.state.value.comments.last()
        repo.reactionFailure = RuntimeException()
        model.toggleReaction(comment, "👍")
        assertTrue(model.state.value.comments.last().content.reactions.isEmpty())
        assertEquals(ChatViewModel.REACTION_FAILURE, model.state.value.error)
    }

    @Test
    fun toggledReactions() {
        val start = listOf(MessageReaction("👍", 2, true), MessageReaction("🔥", 1, false))
        assertEquals(listOf(MessageReaction("👍", 1, false), MessageReaction("🔥", 2, true)), CommentsModel.toggled(start, "🔥"))
        assertEquals(listOf(MessageReaction("👍", 1, false), MessageReaction("🔥", 1, false)), CommentsModel.toggled(start, "👍"))
        assertEquals(listOf(MessageReaction("❤️", 1, true)), CommentsModel.toggled(emptyList(), "❤️"))
    }

    @Test
    fun labels() {
        assertEquals("Комментировать", commentsLabel(0))
        assertEquals("1 комментарий", commentsLabel(1))
        assertEquals("3 комментария", commentsLabel(3))
        assertEquals("11 комментариев", commentsLabel(11))
        assertEquals("21 комментарий", commentsLabel(21))
    }

    @Test
    fun channelPostsShowFooterAndAskCounts() {
        val messages = FakeMessages()
        repo.countsReply = mapOf("5" to 7)
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0, commentsEnabled = true))
        messages.list.value = listOf(
            Message("5", "10", "0", "пост", 1_000L),
            Message("6", "10", "0", "пост 2", 2_000L),
        )
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L }, comments = repo)
        val bubbles = vm.state.value.items.filterIsInstance<ChatItem.Bubble>().associate { it.message.id to it.comments }
        assertEquals(mapOf("5" to 7, "6" to 0), bubbles)
        assertEquals(listOf(listOf("5", "6")), repo.asked)
        vm.openComments(messages.list.value.first())
        assertEquals("5", vm.commentsModel.value?.post?.id)
        vm.closeComments()
        assertNull(vm.commentsModel.value)
        assertEquals(listOf("5"), repo.asked.last())
    }

    @Test
    fun noFooterOutsideChannelsOrWhenDisabled() {
        val messages = FakeMessages()
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0, commentsEnabled = false))
        messages.list.value = listOf(Message("5", "10", "0", "пост", 1_000L, content = MessageContent(comments = 3)))
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L }, comments = repo)
        assertNull(vm.state.value.items.filterIsInstance<ChatItem.Bubble>().single().comments)
        assertTrue(repo.asked.isEmpty())
    }
}
