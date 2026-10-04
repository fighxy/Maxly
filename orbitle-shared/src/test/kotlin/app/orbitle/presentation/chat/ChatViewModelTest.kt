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
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.TextSpan
import app.orbitle.domain.ServerFolder
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
    override suspend fun loadLatest(chatId: String) = Unit
    override suspend fun loadOlder(chatId: String): Boolean {
        olderCalls++
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
    fun failedReactionSyncRetriesOnNextHistory() {
        repo.syncFailure = IllegalStateException("сеть")
        val model = vm()
        repo.list.value = listOf(msg("15"))
        assertEquals(listOf(listOf("15")), repo.synced)
        repo.syncFailure = null
        repo.list.value = listOf(msg("15"), msg("16"))
        assertEquals(listOf(listOf("15"), listOf("15", "16")), repo.synced)
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
    override suspend fun members(chatId: String): List<ChatMemberRow> {
        calls++
        if (failures > 0) {
            failures--
            throw IllegalStateException("сеть")
        }
        return listOf(ChatMemberRow("42", "Анна"))
    }
}
