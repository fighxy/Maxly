package app.maxly.presentation.chat

import app.maxly.MainDispatcherRule
import app.maxly.data.CoreDraftRepository
import app.maxly.data.DraftRepository
import app.maxly.domain.ChatDraft
import app.maxly.domain.Message
import app.maxly.domain.TextSpan
import com.maxly.core.api.Drafts
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * Сервер черновиков в памяти: сохранение ставит своё время. [marks] — отметки стирания, как их
 * держит стор ядра; выбор черновика для поля — правилом ядра [Drafts.reconcile].
 */
class FakeDraftServer : DraftRepository {
    val stored = MutableStateFlow<Map<String, ChatDraft>>(emptyMap())
    val marks = mutableMapOf<String, Long>()
    val saves = mutableListOf<Pair<String, ChatDraft>>()
    val discards = mutableListOf<String>()
    var clock = 10_000L
    override val drafts = stored
    override fun current(chatId: String) = stored.value[chatId]
    override fun reconcile(chatId: String, local: ChatDraft?): ChatDraft? {
        val id = chatId.toLongOrNull() ?: 0L
        val server = stored.value[chatId]?.let { CoreDraftRepository.maxDraft(id, it) }
        return CoreDraftRepository.reconcile(id, local) { mine -> Drafts.reconcile(mine, server, marks[chatId]) }
    }

    /** Черновик стёрли на другом устройстве в [time] (пуш 153). */
    fun discardedElsewhere(chatId: String, time: Long) {
        marks[chatId] = time
        stored.update { it - chatId }
    }
    override suspend fun save(chatId: String, draft: ChatDraft) {
        saves += chatId to draft
        stored.update { it + (chatId to draft.copy(updatedAtMs = ++clock)) }
    }
    override suspend fun discard(chatId: String) {
        discards += chatId
        stored.update { it - chatId }
    }
}

/** Черновики устройства целиком, как их хранит приложение. */
class MemoryFullDrafts : DraftStore {
    val map = mutableMapOf<String, ChatDraft>()
    override fun get(chatId: String) = map[chatId]?.text
    override fun put(chatId: String, text: String) = save(chatId, ChatDraft(text, 0))
    override fun load(chatId: String) = map[chatId]
    override fun save(chatId: String, draft: ChatDraft?) {
        if (draft == null || draft.isEmpty) map.remove(chatId) else map[chatId] = draft
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class DraftSyncTest {
    private val scope = TestScope(StandardTestDispatcher())
    private val server = FakeDraftServer()
    private val sync = DraftSync(scope, server, delayMs = 1_500)

    @Test
    fun typingIsSavedOnceAfterAPause() {
        sync.changed("1", ChatDraft("п", 1))
        scope.advanceTimeBy(1_000)
        sync.changed("1", ChatDraft("привет", 2))
        scope.advanceTimeBy(1_000)
        scope.runCurrent()
        assertTrue(server.saves.isEmpty())
        scope.advanceTimeBy(600)
        scope.runCurrent()
        assertEquals(listOf("привет"), server.saves.map { it.second.text })
    }

    @Test
    fun leavingTheChatSendsAtOnce() {
        sync.changed("1", ChatDraft("привет", 1))
        sync.flush("1")
        scope.runCurrent()
        assertEquals(1, server.saves.size)
        // Нечего отправлять — уход ничего не шлёт.
        sync.flush("1")
        scope.runCurrent()
        assertEquals(1, server.saves.size)
    }

    @Test
    fun clearedDraftIsDiscardedOnlyWhenTheServerHasOne() {
        sync.changed("1", null)
        scope.advanceTimeBy(2_000)
        scope.runCurrent()
        assertTrue(server.discards.isEmpty())
        server.stored.value = mapOf("1" to ChatDraft("старое", 5))
        sync.changed("1", ChatDraft("  ", 6))
        scope.advanceTimeBy(2_000)
        scope.runCurrent()
        assertEquals(listOf("1"), server.discards)
    }

    @Test
    fun sameDraftAsOnTheServerIsNotSavedAgain() {
        val marks = listOf(TextSpan(TextSpan.Kind.STRONG, 0, 3))
        server.stored.value = mapOf("1" to ChatDraft("abc", 5, marks, "9"))
        sync.changed("1", ChatDraft("abc", 99, marks, "9"))
        sync.flush("1")
        scope.runCurrent()
        assertTrue(server.saves.isEmpty())
        sync.changed("1", ChatDraft("abc", 100, emptyList(), "9"))
        sync.flush("1")
        scope.runCurrent()
        assertEquals(1, server.saves.size)
    }

    @Test
    fun replyWithoutTextIsSavedAndNothingAtAllIsADiscard() {
        sync.changed("1", ChatDraft("", 1, replyTo = "7"))
        sync.flush("1")
        scope.runCurrent()
        assertEquals(listOf("1" to ChatDraft("", 1, replyTo = "7")), server.saves)
        sync.changed("1", ChatDraft("", 2))
        sync.flush("1")
        scope.runCurrent()
        assertEquals(1, server.saves.size)
        assertEquals(listOf("1"), server.discards)
    }

    @Test
    fun sentMessageCancelsThePendingSaveAndLeavesTheDiscardToTheCore() {
        server.stored.value = mapOf("1" to ChatDraft("abc", 5))
        sync.changed("1", ChatDraft("abcd", 6))
        sync.sent("1")
        scope.advanceTimeBy(5_000)
        scope.runCurrent()
        // Отправленный текст не возвращается на сервер; DRAFT_DISCARD после отправки шлёт ядро.
        assertTrue(server.saves.isEmpty())
        assertTrue(server.discards.isEmpty())
        // Уход из чата после отправки ничего не шлёт.
        sync.flush("1")
        scope.runCurrent()
        assertTrue(server.discards.isEmpty())
    }
}

class ChatDraftsTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val local = MemoryFullDrafts()
    private val server = FakeDraftServer()
    private val scope = TestScope(main.dispatcher)
    private val sync = DraftSync(scope, server, delayMs = 1_500)

    private fun vm() = ChatViewModel("10", repo, now = { 5_000L }, drafts = local, draftSync = sync)

    @Test
    fun formattingAndReplySurviveInTheLocalDraft() {
        repo.list.value = listOf(Message("7", "10", "2", "вопрос", 1))
        val first = vm()
        first.beginReply(repo.list.value.first())
        first.setDraft("жирный текст")
        first.toggleFormat(TextSpan.Kind.STRONG, 0, 6)
        val saved = local.map["10"]!!
        assertEquals(listOf(TextSpan(TextSpan.Kind.STRONG, 0, 6)), saved.formatting)
        assertEquals("7", saved.replyTo)

        val second = vm()
        assertEquals("жирный текст", second.state.value.draft)
        assertEquals(listOf(TextSpan(TextSpan.Kind.STRONG, 0, 6)), second.state.value.formatting)
        assertEquals("7", second.state.value.replyTo?.id)
    }

    @Test
    fun replyOnAnEmptyComposerIsADraftThatComesBack() {
        repo.list.value = listOf(Message("7", "10", "2", "вопрос", 1))
        val first = vm()
        first.beginReply(repo.list.value.first())
        assertEquals(ChatDraft("", 5_000, emptyList(), "7"), local.map["10"])
        scope.advanceTimeBy(1_600)
        scope.runCurrent()
        assertEquals(listOf("10" to ChatDraft("", 5_000, emptyList(), "7")), server.saves)

        val second = vm()
        assertEquals("", second.state.value.draft)
        assertEquals("7", second.state.value.replyTo?.id)

        second.cancelReply()
        assertNull(local.map["10"])
        scope.advanceTimeBy(1_600)
        scope.runCurrent()
        assertEquals(listOf("10"), server.discards)
    }

    @Test
    fun serverReplyDraftWaitsForItsMessage() {
        server.stored.value = mapOf("10" to ChatDraft("", 9_000, replyTo = "7"))
        val model = vm()
        assertNull(model.state.value.replyTo)
        repo.list.value = listOf(Message("7", "10", "2", "вопрос", 1))
        scope.runCurrent()
        assertEquals("7", model.state.value.replyTo?.id)
    }

    @Test
    fun laterDraftWinsBetweenDeviceAndServer() {
        local.map["10"] = ChatDraft("здесь", 1_000)
        server.stored.value = mapOf("10" to ChatDraft("на сервере", 2_000, listOf(TextSpan(TextSpan.Kind.EMPHASIZED, 0, 2))))
        val model = vm()
        assertEquals("на сервере", model.state.value.draft)
        assertEquals(listOf(TextSpan(TextSpan.Kind.EMPHASIZED, 0, 2)), model.state.value.formatting)

        local.map["10"] = ChatDraft("здесь", 3_000)
        assertEquals("здесь", vm().state.value.draft)
    }

    @Test
    fun discardAtTheSameTimeBeatsTheDeviceDraft() {
        local.map["10"] = ChatDraft("здесь", 1_000)
        server.marks["10"] = 1_000
        val model = vm()
        assertEquals("", model.state.value.draft)
        assertNull(local.map["10"])
        assertTrue(server.discards.isEmpty())

        local.map["10"] = ChatDraft("здесь", 1_001)
        assertEquals("здесь", vm().state.value.draft)
    }

    @Test
    fun discardElsewhereClearsAnUntouchedComposer() {
        server.stored.value = mapOf("10" to ChatDraft("на сервере", 2_000))
        val model = vm()
        assertEquals("на сервере", model.state.value.draft)
        server.discardedElsewhere("10", 3_000)
        scope.runCurrent()
        assertEquals("", model.state.value.draft)
        assertNull(local.map["10"])
    }

    @Test
    fun discardElsewhereKeepsTypedText() {
        server.stored.value = mapOf("10" to ChatDraft("на сервере", 2_000))
        val model = vm()
        model.setDraft("моё")
        server.discardedElsewhere("10", 3_000)
        scope.runCurrent()
        assertEquals("моё", model.state.value.draft)
    }

    @Test
    fun typingReachesTheServerAfterThePauseAndSendLeavesTheDiscardToTheCore() {
        val model = vm()
        model.setDraft("привет")
        assertTrue(server.saves.isEmpty())
        scope.advanceTimeBy(1_600)
        scope.runCurrent()
        assertEquals("привет", server.stored.value["10"]?.text)
        model.send()
        scope.advanceTimeBy(1_600)
        scope.runCurrent()
        assertNull(local.map["10"])
        // DRAFT_DISCARD после отправки шлёт ядро; клиент ни стирает, ни пересохраняет.
        assertTrue(server.discards.isEmpty())
        assertEquals(1, server.saves.size)
    }

    @Test
    fun serverDraftArrivingLaterFillsAnUntouchedComposer() {
        val model = vm()
        server.stored.value = mapOf("10" to ChatDraft("с телефона", 9_000))
        assertEquals("с телефона", model.state.value.draft)
        model.setDraft("моё")
        server.stored.value = mapOf("10" to ChatDraft("снова с телефона", 9_500))
        assertEquals("моё", model.state.value.draft)
    }
}
