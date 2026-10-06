package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.ChatMemberRow
import app.orbitle.data.ChatRepository
import app.orbitle.data.MessageRepository
import app.orbitle.domain.PinNotice
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageReaction
import app.orbitle.data.CoreFailure
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.TextSpan
import app.orbitle.domain.ServerFolder
import app.orbitle.domain.InlineButton
import app.orbitle.domain.InlineKeyboard
import app.orbitle.data.ButtonAnswer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class FakeMessages : MessageRepository {
    override val currentUserId: String = "1"
    val list = MutableStateFlow<List<Message>>(emptyList())
    val headerInfo = MutableStateFlow<ChatHeaderInfo?>(null)
    val sent = mutableListOf<Pair<String, String?>>()
    val edits = mutableListOf<Pair<String, String>>()
    val deletes = mutableListOf<Pair<List<String>, Boolean>>()
    val reads = mutableListOf<String>()
    val reactions = mutableListOf<Pair<String, String?>>()
    var olderCalls = 0
    var hasOlder = true
    var sendFailure: Exception? = null
    var editFailure: Exception? = null
    var catalog = listOf("👍", "❤️")

    override fun messages(chatId: String) = list
    override fun header(chatId: String) = headerInfo.map { it }
    var latestFailure: Exception? = null
    var olderFailure: Exception? = null
    var latestCalls = 0
    override suspend fun loadLatest(chatId: String) {
        latestCalls++
        latestFailure?.let { throw it }
    }
    override suspend fun loadOlder(chatId: String): Boolean {
        olderCalls++
        olderFailure?.let { throw it }
        return hasOlder
    }
    override suspend fun send(chatId: String, text: String, replyTo: String?) {
        sent += text to replyTo
        sendFailure?.let { throw it }
    }
    val forwards = mutableListOf<Triple<String, String, String>>()
    var forwardFailure: Exception? = null
    override suspend fun forward(chatId: String, messageId: String, targetChatId: String) {
        forwardFailure?.let { throw it }
        forwards += Triple(chatId, messageId, targetChatId)
    }
    override suspend fun retry(chatId: String, localId: String) = Unit
    override fun discard(chatId: String, localId: String) {
        list.value = list.value.filterNot { it.id == localId }
    }
    override suspend fun edit(chatId: String, messageId: String, text: String) {
        edits += messageId to text
        editFailure?.let { throw it }
    }
    override suspend fun delete(chatId: String, messageIds: List<String>, forEveryone: Boolean) {
        deletes += messageIds to forEveryone
    }
    override suspend fun markRead(chatId: String, messageId: String) {
        reads += messageId
    }
    val unreadMarks = mutableListOf<Long>()
    var unreadFailure: Exception? = null
    var unreadGate: kotlinx.coroutines.CompletableDeferred<Unit>? = null
    override suspend fun markUnread(chatId: String, fromMs: Long): Int {
        unreadMarks += fromMs
        unreadGate?.await()
        unreadFailure?.let { throw it }
        return 2
    }
    override suspend fun react(chatId: String, messageId: String, emoji: String?) {
        reactions += messageId to emoji
    }
    val synced = mutableListOf<List<String>>()
    var syncFailure: Exception? = null
    override suspend fun syncReactions(chatId: String, messageIds: List<String>) {
        synced += messageIds
        syncFailure?.let { throw it }
    }
    val formatted = mutableListOf<List<TextSpan>>()
    override suspend fun sendFormatted(chatId: String, text: String, replyTo: String?, marks: List<TextSpan>) {
        formatted += marks
        send(chatId, text, replyTo)
    }
    override suspend fun reactionCatalog() = catalog

    val media = mutableListOf<Triple<List<app.orbitle.domain.OutgoingFile>, String, String?>>()
    var mediaGate: kotlinx.coroutines.CompletableDeferred<Unit>? = null
    override suspend fun sendMedia(chatId: String, items: List<app.orbitle.domain.OutgoingFile>, caption: String, replyTo: String?, progress: (Float) -> Unit) {
        media += Triple(items, caption, replyTo)
        progress(0.4f)
        mediaGate?.await()
    }

    var transcript: String? = "Привет"
    var transcribeFailure: Exception? = null
    val transcribeCalls = mutableListOf<Pair<String, String>>()
    val pushes = kotlinx.coroutines.flow.MutableSharedFlow<Pair<String, String>>(extraBufferCapacity = 8)
    var link = "https://cdn.example/v.mp4"
    val linkCalls = mutableListOf<String>()

    override suspend fun transcribe(chatId: String, messageId: String, voiceId: String): String? {
        transcribeCalls += messageId to voiceId
        transcribeFailure?.let { throw it }
        return transcript
    }
    override fun transcriptions() = pushes
    override suspend fun mediaLink(chatId: String, messageId: String, attachment: app.orbitle.domain.ChatAttachment): String {
        linkCalls += attachment.id
        return link
    }
}

class ChatViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val day = 86_400_000L
    private val now = 1_790_683_200_000L // 2026-09-29 12:00 UTC
    private fun vm(chatId: String = "10", chats: ChatRepository? = null) =
        ChatViewModel(chatId, repo, ChatFormatter(ZoneOffset.UTC), now = { now }, chats = chats)

    private fun msg(id: String, author: String = "2", at: Long = now, text: String = "т$id", status: MessageStatus = MessageStatus.SENT, name: String = "Анна", content: MessageContent = MessageContent.empty, service: Boolean = false) =
        Message(id = id, chatId = "10", authorId = author, text = text, timeMs = at, status = status, authorName = name, content = content, isService = service)

    private fun chat(type: ChatType = ChatType.PRIVATE, unread: Int = 0) =
        Chat(id = "10", title = "Анна", type = type, updatedAtMs = now, unreadCount = unread, isOnline = true)

    @Test
    fun rateLimitKeepsStoredFeedQuiet() {
        repo.list.value = listOf(msg("1"))
        repo.latestFailure = OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE)
        val model = vm()
        assertNull(model.messages.value)
        assertFalse(model.state.value.isLoading)
    }

    @Test
    fun rateLimitOnEmptyChatExplainsThePauseAndRetries() {
        repo.latestFailure = OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE)
        val model = vm()
        // Не «Здесь пока нет сообщений»: история просто не пришла. Снекбара нет — он закрыл бы низ.
        assertEquals(ChatViewModel.RATE_LIMIT_HINT, model.state.value.emptyHint)
        assertNull(model.messages.value)
        repo.latestFailure = null
        repo.list.value = listOf(msg("1"))
        main.dispatcher.scheduler.advanceTimeBy(ChatViewModel.RATE_LIMIT_RETRY_MS + 1)
        main.dispatcher.scheduler.runCurrent()
        assertNull(model.state.value.emptyHint)
        assertEquals(1, model.state.value.items.count { it is ChatItem.Bubble })
    }

    @Test
    fun refusedChatStopsRetryingAfterAFewTries() {
        repo.latestFailure = OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE)
        val model = vm()
        // Открытие и три повтора с паузами 20, 40 и 80 с — и всё: каждый отказ продлевает лимит.
        main.dispatcher.scheduler.advanceTimeBy(10 * 60_000L)
        main.dispatcher.scheduler.runCurrent()
        assertEquals(1 + ChatViewModel.LATEST_RETRY_LIMIT, repo.latestCalls)
        assertEquals(ChatViewModel.RATE_LIMIT_GAVE_UP_HINT, model.state.value.emptyHint)
    }

    @Test
    fun emptyChatAfterRetrySaysSo() {
        repo.latestFailure = OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE)
        val model = vm()
        repo.latestFailure = null
        main.dispatcher.scheduler.advanceTimeBy(ChatViewModel.RATE_LIMIT_RETRY_MS + 1)
        main.dispatcher.scheduler.runCurrent()
        assertEquals("Здесь пока нет сообщений", model.state.value.emptyHint)
    }

    @Test
    fun olderPagePausesAfterFailure() {
        repo.list.value = listOf(msg("1"), msg("2"))
        repo.olderFailure = OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE)
        val model = vm()
        model.loadOlder()
        assertEquals(1, repo.olderCalls)
        // Пауза сервера: без снекбара, и следующая прокрутка вверх не повторяет запрос сразу.
        assertNull(model.messages.value)
        model.loadOlder()
        assertEquals(1, repo.olderCalls)
    }

    @Test
    fun composerOnlyWhereYouCanWrite() {
        // Чата нет в сторе (канал из поиска): поле ввода не показывается.
        assertFalse(vm().state.value.canWrite)
        repo.headerInfo.value = ChatHeaderInfo(chat())
        assertTrue(vm().state.value.canWrite)
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.CHANNEL).copy(canWrite = false))
        assertFalse(vm().state.value.canWrite)
        // «Избранное» пишется всегда, даже пока его строки нет в сторе.
        repo.headerInfo.value = null
        assertTrue(vm(chatId = Chat.SAVED_MESSAGES_ID).state.value.canWrite)
    }

    @Test
    fun muteButtonInsteadOfComposerInAChannel() {
        val chats = FakeChats()
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.CHANNEL).copy(canWrite = false))
        val model = vm(chats = chats)
        assertEquals(false, model.state.value.muted)
        model.toggleMute()
        assertEquals(true, model.state.value.muted)
        assertEquals(listOf("10" to true), chats.mutes)
        // Стор отразил звук — кнопка та же.
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.CHANNEL).copy(canWrite = false, isMuted = true))
        assertEquals(true, model.state.value.muted)
        // Писать можно — кнопки звука нет, есть поле ввода.
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.GROUP))
        assertNull(model.state.value.muted)
        // Канал вне списка: вместо кнопки звука «Подписаться».
        repo.headerInfo.value = null
        assertNull(vm(chats = chats).state.value.muted)
    }

    @Test
    fun itemsNewestFirstWithDaySeparators() {
        val model = vm()
        repo.list.value = listOf(msg("1", at = now - day), msg("2", at = now - 60_000), msg("3", author = "1", at = now))
        val keys = model.state.value.items.map { it.key }
        assertEquals(listOf("3", "2", "day-2026-09-29", "1", "day-2026-09-28"), keys)
        assertEquals("Сегодня", (model.state.value.items[2] as ChatItem.Day).label)
        assertTrue((model.state.value.items[0] as ChatItem.Bubble).outgoing)
        assertFalse(model.state.value.isLoading)
    }

    @Test
    fun groupShowsAuthorOnFirstAndAvatarOnLast() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.GROUP), participants = 3)
        repo.list.value = listOf(msg("1", at = now - 3), msg("2", at = now - 2), msg("3", author = "5", name = "Борис", at = now - 1))
        val bubbles = model.state.value.items.filterIsInstance<ChatItem.Bubble>().associateBy { it.key }
        assertEquals("Анна", bubbles["1"]!!.authorName)
        assertNull(bubbles["2"]!!.authorName)
        assertFalse(bubbles["1"]!!.showsAvatar)
        assertTrue(bubbles["2"]!!.showsAvatar)
        assertTrue(bubbles["1"]!!.continues)
        assertEquals("Борис", bubbles["3"]!!.authorName)
        assertEquals("3 участника", model.state.value.header!!.subtitle)
        assertTrue(bubbles["2"]!!.joinsPrevious)
        assertFalse(bubbles["3"]!!.joinsPrevious)
    }

    @Test
    fun sameAuthorWithinFifteenMinutesGlues() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.GROUP), participants = 3)
        repo.list.value = listOf(msg("1", at = now - BubbleCorners.ATTACH_WINDOW_MS), msg("2", at = now))
        val bubbles = model.state.value.items.filterIsInstance<ChatItem.Bubble>().associateBy { it.key }
        assertTrue(bubbles["1"]!!.continues)
        assertFalse(bubbles["1"]!!.joinsPrevious)
        assertTrue(bubbles["2"]!!.joinsPrevious)
        assertFalse(bubbles["2"]!!.continues)
        assertEquals("Анна", bubbles["1"]!!.authorName)
        assertNull(bubbles["2"]!!.authorName)
        assertFalse(bubbles["1"]!!.showsAvatar)
        assertTrue(bubbles["2"]!!.showsAvatar)
    }

    @Test
    fun sameAuthorAfterFifteenMinutesSplits() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.GROUP), participants = 3)
        repo.list.value = listOf(msg("1", at = now - BubbleCorners.ATTACH_WINDOW_MS - 60_000), msg("2", at = now))
        val bubbles = model.state.value.items.filterIsInstance<ChatItem.Bubble>().associateBy { it.key }
        assertFalse(bubbles["1"]!!.continues)
        assertFalse(bubbles["2"]!!.joinsPrevious)
        assertEquals("Анна", bubbles["1"]!!.authorName)
        assertEquals("Анна", bubbles["2"]!!.authorName)
        assertTrue(bubbles["1"]!!.showsAvatar)
        assertTrue(bubbles["2"]!!.showsAvatar)
    }

    @Test
    fun serviceAndDayBreakTheSeries() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.GROUP), participants = 3)
        repo.list.value = listOf(
            msg("1", at = now - 50_000),
            msg("s", at = now - 25_000, text = "Анна добавила Бориса", service = true),
            msg("2", at = now),
        )
        val bubbles = model.state.value.items.filterIsInstance<ChatItem.Bubble>().associateBy { it.key }
        assertFalse(bubbles["1"]!!.continues)
        assertFalse(bubbles["2"]!!.joinsPrevious)
        assertEquals("Анна", bubbles["1"]!!.authorName)
        assertEquals("Анна", bubbles["2"]!!.authorName)

        val midnight = 12 * 60 * 60 * 1000L
        val five = 5 * 60 * 1000L
        repo.list.value = listOf(msg("a", at = now - midnight - five), msg("b", at = now - midnight + five))
        val across = model.state.value.items.filterIsInstance<ChatItem.Bubble>().associateBy { it.key }
        assertFalse(across["a"]!!.continues)
        assertFalse(across["b"]!!.joinsPrevious)
        assertTrue(model.state.value.items.any { it is ChatItem.Day })
    }

    @Test
    fun headerSubtitleForDialogAndTyping() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat())
        assertEquals("в сети", model.state.value.header!!.subtitle)
        assertTrue(model.state.value.header!!.subtitleAccent)
        repo.headerInfo.value = ChatHeaderInfo(chat(), typing = listOf("Анна"))
        assertEquals("печатает…", model.state.value.header!!.subtitle)
    }

    @Test
    fun sendClearsDraftAndPassesReply() {
        val model = vm()
        repo.list.value = listOf(msg("7"))
        model.beginReply(repo.list.value.first())
        model.setDraft("  привет  ")
        assertTrue(model.state.value.canSend)
        model.send()
        assertEquals(listOf("привет" to "7"), repo.sent)
        assertEquals("", model.state.value.draft)
        assertNull(model.state.value.replyTo)
    }

    @Test
    fun blankDraftIsNotSent() {
        val model = vm()
        model.setDraft("   ")
        model.send()
        assertTrue(repo.sent.isEmpty())
    }

    @Test
    fun sendFailureIsShown() {
        val model = vm()
        repo.sendFailure = OrbitleError.NetworkUnavailable
        model.setDraft("x")
        model.send()
        assertEquals("Нет соединения с сервером", model.messages.value)
    }

    @Test
    fun reactionsAskedOncePerShownServerMessage() {
        val model = vm()
        repo.list.value = listOf(msg("local-1", status = MessageStatus.SENDING), msg("15"))
        assertEquals(listOf(listOf("15")), repo.synced)
        repo.list.value = listOf(msg("local-1", status = MessageStatus.SENDING), msg("15"), msg("16"))
        assertEquals(listOf(listOf("15"), listOf("16")), repo.synced)
        assertTrue(model.state.value.items.isNotEmpty())
    }

    @Test
    fun failedReactionSyncWaitsBeforeRetry() {
        var clock = now
        repo.syncFailure = IllegalStateException("сеть")
        val model = ChatViewModel("10", repo, ChatFormatter(ZoneOffset.UTC), now = { clock })
        repo.list.value = listOf(msg("15"))
        assertEquals(listOf(listOf("15")), repo.synced)
        repo.syncFailure = null
        // Сразу после ошибки обновления ленты не повторяют запрос: иначе шквал и too.many.requests.
        repo.list.value = listOf(msg("15"), msg("16"))
        assertEquals(listOf(listOf("15")), repo.synced)
        clock += ChatViewModel.RETRY_AFTER_ERROR_MS
        repo.list.value = listOf(msg("15"), msg("16"), msg("17"))
        assertEquals(listOf(listOf("15"), listOf("15", "16", "17")), repo.synced)
        assertTrue(model.state.value.items.isNotEmpty())
    }

    @Test
    fun animojiSendKeepsMark() {
        val model = vm()
        model.noteAnimoji(AnimatedEmoji(id = "5", emoji = "🔥", lottieUrl = "https://x/5.json"))
        model.setDraft("🔥")
        model.send()
        assertEquals(listOf("🔥" to null), repo.sent)
        val span = repo.formatted.single().single()
        assertEquals(TextSpan.Kind.ANIMOJI, span.kind)
        assertEquals(0, span.from)
        assertEquals(2, span.length)
        assertEquals("5", span.entityId)
        assertEquals("https://x/5.json", span.url)
        assertEquals("", model.state.value.draft)
    }

    @Test
    fun editFlowRestoresDraft() {
        val model = vm()
        val own = msg("8", author = "1", text = "старый")
        repo.list.value = listOf(own)
        model.setDraft("черновик")
        assertTrue(model.canEdit(own))
        model.beginEdit(own)
        assertEquals("старый", model.state.value.draft)
        model.setDraft("новый")
        model.send()
        assertEquals(listOf("8" to "новый"), repo.edits)
        assertEquals("черновик", model.state.value.draft)
        assertNull(model.state.value.editing)
    }

    @Test
    fun failedEditGoesBackToComposer() {
        val model = vm()
        val own = msg("8", author = "1", text = "старый")
        repo.editFailure = OrbitleError.Rejected("нельзя")
        model.beginEdit(own)
        model.setDraft("новый")
        model.send()
        assertEquals(own, model.state.value.editing)
        assertEquals("новый", model.state.value.draft)
        assertEquals("нельзя", model.messages.value)
    }

    @Test
    fun cancelEditRestoresDraft() {
        val model = vm()
        model.setDraft("черновик")
        model.beginEdit(msg("8", author = "1"))
        model.cancelEdit()
        assertEquals("черновик", model.state.value.draft)
    }

    @Test
    fun cannotEditForeignOrForwardedOrPending() {
        val model = vm()
        assertFalse(model.canEdit(msg("1")))
        assertFalse(model.canEdit(msg("local-1", author = "1", status = MessageStatus.SENDING)))
        assertFalse(model.canEdit(msg("2", author = "1", content = MessageContent(forward = app.orbitle.domain.MessageForward("Борис", "x")))))
    }

    @Test
    fun deleteRules() {
        val model = vm()
        val own = msg("9", author = "1")
        assertTrue(model.canDeleteForEveryone(own))
        assertFalse(model.canDeleteForEveryone(msg("9")))
        model.delete(own, forEveryone = true)
        assertEquals(listOf(listOf("9") to true), repo.deletes)
        val saved = vm(Chat.SAVED_MESSAGES_ID)
        assertFalse(saved.canDeleteForEveryone(own))
        saved.delete(own, forEveryone = false)
        assertEquals(listOf("9") to true, repo.deletes.last())
    }

    @Test
    fun deletingPendingMessageDiscardsIt() {
        val model = vm()
        val pending = msg("local-1", author = "1", status = MessageStatus.FAILED)
        repo.list.value = listOf(pending)
        model.delete(pending, forEveryone = false)
        assertTrue(repo.deletes.isEmpty())
        assertTrue(repo.list.value.isEmpty())
    }

    @Test
    fun reactionToggles() {
        val model = vm()
        val message = msg("4", content = MessageContent(reactions = listOf(MessageReaction("👍", 2, mine = true))))
        model.toggleReaction(message, "👍")
        model.toggleReaction(message, "🔥")
        assertEquals(listOf("4" to null, "4" to "🔥"), repo.reactions)
        assertEquals(listOf("👍", "❤️"), model.state.value.quickReactions)
        assertFalse(model.canReact(msg("local-2", status = MessageStatus.SENDING)))
    }

    @Test
    fun marksLatestIncomingAsRead() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat(unread = 1))
        repo.list.value = listOf(msg("1"), msg("2"))
        // Чат с непрочитанными читается тем, что видно: пока экран молчит, отметки нет.
        assertTrue(repo.reads.isEmpty())
        model.onVisible("2", atBottom = true)
        assertEquals("2", repo.reads.last())
        val count = repo.reads.size
        repo.list.value = repo.list.value + msg("local-3", author = "1", status = MessageStatus.SENDING)
        assertEquals(count, repo.reads.size)
        model.setActive(false)
        repo.list.value = repo.list.value + msg("5")
        assertEquals(count, repo.reads.size)
        model.setActive(true)
        assertEquals("5", repo.reads.last())
    }

    @Test
    fun markUnreadSendsTheMessageTimeAndLeaves() {
        val model = vm()
        repo.headerInfo.value = ChatHeaderInfo(chat())
        repo.list.value = listOf(msg("1", at = now - 60_000), msg("2"))
        val reads = repo.reads.size
        val gate = kotlinx.coroutines.CompletableDeferred<Unit>()
        repo.unreadGate = gate
        var left = 0
        model.markUnread(repo.list.value[0]) { left++ }
        // Пока сервер отвечает, новое сообщение не отмечает чат прочитанным.
        repo.list.value = repo.list.value + msg("3")
        assertEquals(reads, repo.reads.size)
        gate.complete(Unit)
        assertEquals(listOf(now - 60_000), repo.unreadMarks)
        assertEquals(1, left)
        // Чат открыли снова — он читается как обычно.
        model.setActive(false)
        model.setActive(true)
        assertEquals("3", repo.reads.last())
    }

    @Test
    fun markUnreadFailureStaysInTheChat() {
        val model = vm()
        repo.unreadFailure = CoreFailure("NETWORK", null)
        var left = 0
        model.markUnread(msg("1")) { left++ }
        assertEquals(0, left)
        assertEquals("Нет соединения с сервером", model.messages.value)
        assertTrue(model.canMarkUnread(msg("1")))
        assertFalse(model.canMarkUnread(msg("2", service = true)))
        assertFalse(model.canMarkUnread(msg("local-3", status = MessageStatus.SENDING)))
    }

    @Test
    fun olderPagesStopAtEnd() {
        val model = vm()
        repo.list.value = listOf(msg("1"))
        repo.hasOlder = false
        model.loadOlder()
        model.loadOlder()
        assertEquals(1, repo.olderCalls)
        assertFalse(model.state.value.hasOlder)
    }

    @Test
    fun emptyHints() {
        assertEquals("Здесь пока нет сообщений", vm().state.value.emptyHint)
        assertTrue(vm(Chat.SAVED_MESSAGES_ID).state.value.emptyHint!!.contains("только вы"))
    }

    @Test
    fun savedMessagesHideTheWelcomeKey() {
        val saved = vm(Chat.SAVED_MESSAGES_ID)
        val welcome = msg("1", at = now - day).copy(isService = true, text = " ${app.orbitle.domain.SavedMessagesWelcome.KEY}\n")
        repo.list.value = listOf(welcome)
        // Только приветствие — лента пуста и видна подсказка «Избранного».
        assertTrue(saved.state.value.items.isEmpty())
        assertTrue(saved.state.value.emptyHint!!.contains("только вы"))
        repo.list.value = listOf(welcome, msg("2"))
        assertEquals(listOf("2", "day-2026-09-29"), saved.state.value.items.map { it.key })
        assertNull(saved.state.value.emptyHint)
    }

    @Test
    fun welcomeKeyStaysOutsideSavedMessages() {
        val model = vm()
        repo.list.value = listOf(msg("1", text = app.orbitle.domain.SavedMessagesWelcome.KEY))
        assertEquals(listOf("1", "day-2026-09-29"), model.state.value.items.map { it.key })
    }

    @Test
    fun serviceMessagesBecomeChips() {
        val model = vm()
        repo.list.value = listOf(msg("1").copy(isService = true, text = "Чат создан"), msg("2"))
        val service = model.state.value.items.filterIsInstance<ChatItem.Service>().single()
        assertEquals("Чат создан", service.text)
    }

    @Test
    fun forwardsServerMessagesOnly() {
        val model = vm()
        val sent = msg("5")
        val pending = msg("local-1", author = "1", status = MessageStatus.SENDING)
        assertTrue(model.canForward(sent))
        assertFalse(model.canForward(pending))
        model.forward(pending, "20")
        model.forward(sent, "20")
        assertEquals(listOf(Triple("10", "5", "20")), repo.forwards)
        assertEquals("Сообщение переслано", model.messages.value)
    }

    @Test
    fun forwardFailureShowsError() {
        val model = vm()
        repo.forwardFailure = app.orbitle.domain.OrbitleError.Rejected("Нельзя переслать")
        model.forward(msg("5"), "20")
        assertEquals("Нельзя переслать", model.messages.value)
    }

    @Test
    fun localPinHoldsUntilANewerNoticeArrives() {
        val model = vm()
        val target = msg("9", text = "важно")
        repo.list.value = listOf(target)
        model.pin(target)
        assertEquals("9", model.state.value.pinnedMessageId)
        assertEquals("важно", model.state.value.pinnedText)
        repo.list.value = listOf(target, msg("8", text = "ещё"))
        assertEquals("9", model.state.value.pinnedMessageId)
        val echo = msg("10", text = "закрепил", content = MessageContent(pin = PinNotice("9", "важно")), service = true)
        repo.list.value = listOf(target, echo)
        assertEquals("9", model.state.value.pinnedMessageId)
        val other = msg("11", text = "закрепил", content = MessageContent(pin = PinNotice("12", "другое")), service = true)
        repo.list.value = listOf(target, echo, other)
        assertEquals("12", model.state.value.pinnedMessageId)
        assertEquals("другое", model.state.value.pinnedText)
    }

    @Test
    fun localUnpinHidesBannerUntilHistoryCatchesUp() {
        val model = vm()
        val pinned = msg("10", text = "закрепил", content = MessageContent(pin = PinNotice("9", "важно")), service = true)
        repo.list.value = listOf(msg("9", text = "важно"), pinned)
        assertEquals("9", model.state.value.pinnedMessageId)
        model.unpin()
        assertNull(model.state.value.pinnedMessageId)
        repo.list.value = listOf(msg("9", text = "важно"), pinned, msg("8", text = "рядом"))
        assertNull(model.state.value.pinnedMessageId)
        val released = msg("13", text = "снял", content = MessageContent(pin = PinNotice(null, "")), service = true)
        repo.list.value = listOf(msg("9", text = "важно"), pinned, released)
        assertNull(model.state.value.pinnedMessageId)
    }

    @Test
    fun mentionSurvivesAnEditBeforeIt() {
        val model = vm()
        model.setDraft("привет @ан")
        model.insertMention(ChatMemberRow("42", "Анна"))
        assertEquals("привет @Анна ", model.state.value.draft)
        model.setDraft("эй, привет @Анна ")
        model.send()
        val span = repo.formatted.single().single()
        assertEquals(TextSpan.Kind.MENTION, span.kind)
        assertEquals("эй, привет ".length, span.from)
        assertEquals("@Анна".length, span.length)
        assertEquals("42", span.userId)
    }

    @Test
    fun mentionOffsetsFollowTheTrimmedText() {
        val model = vm()
        model.setDraft("@")
        model.insertMention(ChatMemberRow("42", "Анна"))
        model.setDraft("  @Анна")
        model.send()
        val span = repo.formatted.single().single()
        assertEquals(0, span.from)
        assertEquals("@Анна".length, span.length)
        assertEquals(listOf("@Анна" to null), repo.sent)
    }

    @Test
    fun failedMemberLoadRetriesOnTheNextHint() {
        val chats = FakeChats()
        chats.failures = 1
        val model = vm(chats = chats)
        model.setDraft("@")
        assertEquals(1, chats.calls)
        assertTrue(model.state.value.hints.mentions.isEmpty())
        model.setDraft("@А")
        assertEquals(2, chats.calls)
        assertEquals("Анна", model.state.value.hints.mentions.single().name)
    }

    @Test
    fun unreadSeparatorStandsAboveTheFirstUnreadAndGoesAwayAfterSending() {
        repo.list.value = listOf(msg("1", at = now - 4_000), msg("2", at = now - 3_000), msg("3", author = "1", at = now - 2_000), msg("4", at = now - 1_000))
        repo.headerInfo.value = ChatHeaderInfo(chat(unread = 2))
        val model = vm()
        val items = model.state.value.items
        val divider = items.indexOfFirst { it is ChatItem.Unread }
        // Лента перевёрнута: под разделителем (индекс −1) — второе с конца чужое, «2».
        assertEquals("2", items[divider - 1].key)
        assertEquals(1, items.count { it is ChatItem.Unread })
        model.setDraft("ответ")
        model.send()
        assertTrue(model.state.value.items.none { it is ChatItem.Unread })
    }

    @Test
    fun noSeparatorWithoutUnread() {
        repo.list.value = listOf(msg("1"), msg("2"))
        repo.headerInfo.value = ChatHeaderInfo(chat(unread = 0))
        assertTrue(vm().state.value.items.none { it is ChatItem.Unread })
    }

    @Test
    fun callbackButtonGoesToTheBotAndShowsTheAnswer() {
        val chats = FakeChats()
        chats.answer = ButtonAnswer("Принято", "https://bot.example/next")
        val keyboard = InlineKeyboard("cb", listOf(listOf(InlineButton("CALLBACK", "Да", payload = "yes"))))
        val message = msg("5", content = MessageContent(keyboard = keyboard))
        repo.list.value = listOf(message)
        val model = vm(chats = chats)
        model.pressButton(message, keyboard.rows[0][0])
        assertEquals(listOf("10/5/cb/yes"), chats.pressed)
        assertEquals("Принято", model.messages.value)
        assertEquals("https://bot.example/next", model.openUrl.value)
    }

    @Test
    fun linkAndAppButtonsAreHandledByTheScreen() {
        val chats = FakeChats()
        val message = msg("5")
        val model = vm(chats = chats)
        model.pressButton(message, InlineButton("LINK", "Сайт", url = "https://a.b"))
        assertEquals("https://a.b", model.openUrl.value)
        model.pressButton(message, InlineButton("OPEN_APP", "Игра", webApp = "https://max.ru/bot?startapp=lvl%201", contactId = "99"))
        assertEquals(BotAppRequest("99", "10", "lvl 1", "Игра"), model.botApp.value)
        model.pressButton(message, InlineButton("OPEN_APP", "Чат", webApp = "https://max.ru/bot?startapp=x&chat_id=-42", contactId = "99"))
        assertEquals(BotAppRequest("99", "-42", "x", "Чат"), model.botApp.value)
        assertTrue(chats.pressed.isEmpty())
        model.consumeBotApp()
        assertNull(model.botApp.value)
    }

    @Test
    fun channelOutsideTheListShowsItsCardAndJoins() {
        val chats = FakeChats()
        val card = app.orbitle.domain.ChatProfile(app.orbitle.domain.ChatProfile.Kind.CHANNEL, "10", title = "Новости", link = "https://max.ru/news", participants = 117_844, commentsEnabled = false)
        val profiles = object : app.orbitle.data.ProfileRepository {
            override fun cached(chatId: String) = null
            override suspend fun profile(chatId: String) = card
            override suspend fun sharedPage(chatId: String, tab: app.orbitle.domain.SharedMediaTab, beforeMessageId: String) = emptyList<Message>()
        }
        val model = ChatViewModel("10", repo, ChatFormatter(ZoneOffset.UTC), now = { now }, fallbackTitle = "Чат", chats = chats, profiles = profiles)
        val state = model.state.value
        assertEquals("Новости", state.header!!.title)
        assertEquals(ChatType.CHANNEL, state.header!!.type)
        assertFalse(state.canWrite)
        assertEquals(JoinUi("Подписаться", false), state.join)
        model.join()
        assertEquals(listOf("https://max.ru/news"), chats.joined)
        // Чат встал в стор: шапка из него, кнопки больше нет.
        repo.headerInfo.value = ChatHeaderInfo(chat(ChatType.CHANNEL).copy(title = "Новости", canWrite = false))
        assertNull(model.state.value.join)
    }

    @Test
    fun leavingAChannelClosesTheScreenOnlyAfterTheServerAgrees() {
        val chats = FakeChats()
        val model = vm(chats = chats)
        var closed = 0
        chats.leaveFails = true
        model.leave { closed++ }
        assertEquals(0, closed)
        assertTrue(model.messages.value != null)
        chats.leaveFails = false
        model.leave { closed++ }
        assertEquals(1, closed)
        assertEquals(listOf("10", "10"), chats.left)
    }

    @Test
    fun openAppButtonOfABotHeader() {
        repo.headerInfo.value = ChatHeaderInfo(chat(), botAppId = "77")
        val model = vm()
        assertEquals("77", model.state.value.botAppId)
        model.openBotApp()
        assertEquals(BotAppRequest("77", "10", null, "Анна"), model.botApp.value)
    }
}

private class FakeChats : ChatRepository {
    override val chats: Flow<List<Chat>?> = MutableStateFlow(emptyList())
    override val folders: Flow<List<ServerFolder>> = MutableStateFlow(emptyList())
    override val typing: Flow<Map<String, List<String>>> = MutableStateFlow(emptyMap())
    override suspend fun refresh() = Unit
    override suspend fun setPinned(chatId: String, pinned: Boolean) = Unit
    override fun clear() = Unit
    var failures = 0
    var calls = 0
    var answer = ButtonAnswer(null, null)
    val pressed = mutableListOf<String>()
    val joined = mutableListOf<String>()
    val left = mutableListOf<String>()
    val mutes = mutableListOf<Pair<String, Boolean>>()
    override suspend fun setMuted(chatId: String, muted: Boolean) {
        mutes += chatId to muted
    }
    var leaveFails = false
    override suspend fun leaveChat(chatId: String) {
        left += chatId
        if (leaveFails) throw OrbitleError.Rejected("нельзя")
    }
    override suspend fun joinByLink(link: String): String? {
        joined += link
        return "10"
    }
    override suspend fun pressButton(chatId: String, messageId: String, callbackId: String, payload: String?): ButtonAnswer {
        pressed += "$chatId/$messageId/$callbackId/$payload"
        return answer
    }
    override suspend fun members(chatId: String): List<ChatMemberRow> {
        calls++
        if (failures > 0) {
            failures--
            throw IllegalStateException("сеть")
        }
        return listOf(ChatMemberRow("42", "Анна"))
    }
}
