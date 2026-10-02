package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.MessageRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.flow.MutableStateFlow
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
    private fun vm(chatId: String = "10") = ChatViewModel(chatId, repo, ChatFormatter(ZoneOffset.UTC), now = { now })

    private fun msg(id: String, author: String = "2", at: Long = now, text: String = "т$id", status: MessageStatus = MessageStatus.SENT, name: String = "Анна", content: MessageContent = MessageContent.empty) =
        Message(id = id, chatId = "10", authorId = author, text = text, timeMs = at, status = status, authorName = name, content = content)

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
}
