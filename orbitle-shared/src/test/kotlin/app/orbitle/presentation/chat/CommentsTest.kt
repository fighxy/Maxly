package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.CommentPage
import app.orbitle.data.CommentsRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
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
    var countsFailure: Exception? = null
    var pageCalls = 0
    /** Аргументы первой страницы: время поста и ожидаемое число комментариев. */
    val firstAsked = mutableListOf<Pair<Long?, Int?>>()
    override suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message> {
        pageCalls += 1
        failure?.let { throw it }
        return all.filter { beforeMs == null || it.timeMs < beforeMs }.takeLast(limit)
    }
    override suspend fun firstComments(chatId: String, postId: String, postTimeMs: Long?, expectedCount: Int?, limit: Int): List<Message> {
        firstAsked += postTimeMs to expectedCount
        return comments(chatId, postId, null, limit)
    }
    override suspend fun send(text: String, chatId: String, postId: String): Message {
        sendFailure?.let { throw it }
        sent += text
        return Message("900", chatId, "1", text, 99_000L)
    }
    override suspend fun counts(chatId: String, postIds: List<String>): Map<String, Int> {
        asked += postIds
        countsFailure?.let { throw it }
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
        // Сначала самые новые посты: их видно первыми.
        assertEquals(listOf(listOf("6", "5")), repo.asked)
        assertTrue(vm.canOpenComments(messages.list.value.first()))
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
        assertEquals(false, vm.canOpenComments(messages.list.value.single()))
        assertTrue(repo.asked.isEmpty())
    }

    private val rateLimited = OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE)

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun limitedModel(scheduler: TestCoroutineScheduler) =
        CommentsModel(
            "10", post, "1", repo, CoroutineScope(UnconfinedTestDispatcher(scheduler)), ChatFormatter(ZoneOffset.UTC),
            now = { 100_000L }, knownCount = { 44 }, rateLimitWaitMs = { 15_000L },
        )

    @Test
    fun firstPageAsksWithPostTimeAndKnownCount() {
        model.load()
        model.load()
        assertEquals(listOf(500L to 45), repo.firstAsked)
    }

    @Test
    fun firstPageWaitsOutRateLimitQuietly() {
        val scheduler = TestCoroutineScheduler()
        val limited = limitedModel(scheduler)
        repo.failure = rateLimited
        limited.load()
        assertEquals(CommentsState.Phase.Loading, limited.state.value.phase)
        assertNull(limited.state.value.error)
        assertEquals(1, repo.pageCalls)
        // Повторный вызов во время ожидания не шлёт второй запрос.
        limited.reload()
        assertEquals(1, repo.pageCalls)
        repo.failure = null
        scheduler.advanceTimeBy(14_000)
        scheduler.runCurrent()
        assertEquals(1, repo.pageCalls)
        scheduler.advanceTimeBy(1_001)
        scheduler.runCurrent()
        assertEquals(2, repo.pageCalls)
        assertEquals(CommentsState.Phase.Loaded, limited.state.value.phase)
        assertEquals(30, limited.state.value.comments.size)
        assertEquals(listOf(500L to 44), repo.firstAsked.distinct())
    }

    @Test
    fun rateLimitGivesUpAfterAFewWaits() {
        val scheduler = TestCoroutineScheduler()
        val limited = limitedModel(scheduler)
        repo.failure = rateLimited
        limited.load()
        scheduler.advanceUntilIdle()
        assertEquals(CommentsModel.RATE_LIMIT_RETRIES + 1, repo.pageCalls)
        assertEquals(CommentsState.Phase.Failed(rateLimited.userMessage!!), limited.state.value.phase)
    }

    @Test
    fun olderPageWaitsAfterRateLimitWithoutSnackbar() {
        model.load()
        repo.failure = rateLimited
        model.loadOlder()
        assertNull(model.state.value.error)
        assertEquals(false, model.state.value.isLoadingOlder)
        val calls = repo.pageCalls
        model.loadOlder()
        assertEquals(calls, repo.pageCalls)
    }

    @Test
    fun commentPageAlwaysSendsRealTime() {
        assertEquals(CommentPage(5_000L, 30, 0), CommentPage.before(null, 5_000L, 30))
        assertEquals(CommentPage(1_234L, CommentPage.MAX_PAGE, 0), CommentPage.before(1_234L, 5_000L, 500))
        assertEquals(CommentPage(700L, 0, 30), CommentPage.afterPost(700L, 30))
        assertTrue(CommentPage.before(null, 5_000L, 0).backward >= 1)
    }

    @Test
    fun failedCountsAreRetriedAfterThePause() {
        var clock = 10_000L
        val messages = FakeMessages()
        repo.countsFailure = rateLimited
        repo.countsReply = mapOf("5" to 2)
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0, commentsEnabled = true))
        messages.list.value = listOf(Message("5", "10", "0", "пост", 1_000L))
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { clock }, comments = repo)
        assertEquals(1, repo.asked.size)
        // Счётчика ещё нет: плашка «Комментировать» без числа.
        assertEquals(0, vm.state.value.items.filterIsInstance<ChatItem.Bubble>().single().comments)
        // Обновление ленты во время паузы не повторяет запрос.
        messages.list.value = messages.list.value + Message("6", "10", "0", "пост 2", 2_000L)
        assertEquals(1, repo.asked.size)
        repo.countsFailure = null
        // Пауза — не меньше RATE_LIMIT_RETRY_MS и не больше самой длинной паузы чтений (2 мин).
        clock += 130_000L
        main.dispatcher.scheduler.advanceTimeBy(130_000L)
        main.dispatcher.scheduler.runCurrent()
        assertEquals(listOf("6", "5"), repo.asked.last())
        val bubbles = vm.state.value.items.filterIsInstance<ChatItem.Bubble>().associate { it.message.id to it.comments }
        // Счётчик пришёл только у первого поста; у второго плашка без числа.
        assertEquals(mapOf("5" to 2, "6" to 0), bubbles)
    }

    @Test
    fun countsGoInPacedBatchesOneAtATime() {
        val messages = FakeMessages()
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0, commentsEnabled = true))
        messages.list.value = (1..120).map { Message("$it", "10", "0", "пост $it", 1_000L * it) }
        ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L }, comments = repo)
        assertEquals(1, repo.asked.size)
        assertEquals("120", repo.asked.first().first())
        assertEquals(ChatViewModel.COUNTS_BATCH, repo.asked.first().size)
        main.dispatcher.scheduler.advanceTimeBy(ChatViewModel.COUNTS_PACE_MS + 1)
        main.dispatcher.scheduler.runCurrent()
        assertEquals(2, repo.asked.size)
        main.dispatcher.scheduler.advanceUntilIdle()
        assertEquals(3, repo.asked.size)
        assertEquals(120, repo.asked.flatten().toSet().size)
    }

    @Test
    fun commentsFlagSurvivesAChatCardWithoutOptions() {
        val messages = FakeMessages()
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0, commentsEnabled = true))
        messages.list.value = listOf(Message("5", "10", "0", "пост", 1_000L))
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L }, comments = repo)
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 1))
        messages.list.value = messages.list.value + Message("6", "10", "0", "пост 2", 2_000L)
        val bubbles = vm.state.value.items.filterIsInstance<ChatItem.Bubble>().associate { it.message.id to it.comments }
        assertEquals(mapOf("5" to 0, "6" to 0), bubbles)
    }

    @Test
    fun noCommentsWithoutTheChannelOption() {
        val messages = FakeMessages()
        // Опции COMMENTS нет: родных комментариев нет, даже если у поста пришёл счётчик.
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0))
        messages.list.value = listOf(Message("5", "10", "0", "пост", 1_000L, content = MessageContent(comments = 4)))
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L }, comments = repo)
        assertNull(vm.state.value.items.filterIsInstance<ChatItem.Bubble>().single().comments)
        assertTrue(repo.asked.isEmpty())
    }

    @Test
    fun listedChannelWithoutOptionsTakesTheFlagFromItsCard() {
        val messages = FakeMessages()
        // Строка списка без опций, а в полной карточке комментарии включены.
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Канал", ChatType.CHANNEL, updatedAtMs = 0))
        messages.list.value = listOf(Message("5", "10", "0", "пост", 1_000L))
        val card = app.orbitle.domain.ChatProfile(app.orbitle.domain.ChatProfile.Kind.CHANNEL, "10", "Канал", commentsEnabled = true)
        val profiles = object : app.orbitle.data.ProfileRepository {
            override fun cached(chatId: String) = null
            override suspend fun profile(chatId: String) = card
            override suspend fun sharedPage(chatId: String, tab: app.orbitle.domain.SharedMediaTab, beforeMessageId: String) = emptyList<Message>()
        }
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L }, comments = repo, profiles = profiles)
        assertEquals(0, vm.state.value.items.filterIsInstance<ChatItem.Bubble>().single().comments)
    }
}
