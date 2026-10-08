package app.orbitle.presentation.chat

import app.orbitle.data.MessageRepository
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageForward
import app.orbitle.domain.MessageReader
import app.orbitle.domain.MessageStatus
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.lang.reflect.Proxy
import java.time.ZoneOffset

class MessageInfoModelTest {
    private val zone = ZoneOffset.ofHours(7)
    private val sent = 1_791_452_640_000L // 8 октября 2026, 16:44 (UTC+7)

    private class Readers(private val answer: () -> List<MessageReader>?) : MessageRepository by unused() {
        var asked = 0
        override suspend fun messageReaders(chatId: String, messageId: String): List<MessageReader>? {
            asked++
            return answer()
        }
    }

    private fun model(type: ChatType, message: Message = message(), mine: Boolean = true, repo: MessageRepository = Readers { emptyList() }) =
        MessageInfoModel("10", message, type, mine, repo, TestScope(UnconfinedTestDispatcher()), zone)

    private fun message(content: MessageContent = MessageContent.empty, isRead: Boolean = false, status: MessageStatus = MessageStatus.SENT) =
        Message(id = "77", chatId = "10", authorId = "1", text = "привет", timeMs = sent, status = status, content = content, isRead = isRead)

    @Test
    fun rowsShowSendTimeEditAndForward() {
        val info = model(ChatType.GROUP, message(MessageContent(edited = true, forward = MessageForward("Анна", "текст"))))
        assertEquals(
            listOf(
                MessageInfoModel.Row("Отправлено", "8 октября 2026, 16:44"),
                MessageInfoModel.Row("Изменено", ""),
                MessageInfoModel.Row("Переслано из", "Анна"),
            ),
            info.rows,
        )
    }

    @Test
    fun editTimeIsShownWhenServerSentIt() {
        val info = model(ChatType.GROUP, message(MessageContent(edited = true, editedAtMs = sent + 3_600_000)))
        assertEquals(MessageInfoModel.Row("Изменено", "8 октября 2026, 17:44"), info.rows[1])
    }

    @Test
    fun privateChatShowsDeliveryOfOwnMessageInsteadOfReaders() {
        val repo = Readers { error("не спрашивать") }
        val read = model(ChatType.PRIVATE, message(isRead = true), repo = repo).also { it.load() }
        assertEquals(MessageInfoModel.Row("Статус", "Прочитано"), read.rows.last())
        assertEquals(MessageInfoState.Phase.Unavailable, read.state.value.phase)
        assertEquals(MessageInfoModel.Row("Статус", "Доставлено"), model(ChatType.PRIVATE).rows.last())
        assertEquals(1, model(ChatType.PRIVATE, mine = false).rows.size)
        assertEquals(0, repo.asked)
    }

    @Test
    fun groupLoadsReadersAndSaysWhenNobodyReadYet() {
        val people = listOf(MessageReader("2", "Пётр", emoji = "👍"), MessageReader("3", ""))
        val loaded = model(ChatType.GROUP, repo = Readers { people }).also { it.load() }
        assertEquals(people, loaded.state.value.readers)
        assertNull(loaded.state.value.emptyText)
        assertEquals("Пользователь", MessageInfoModel.name(people[1]))
        val empty = model(ChatType.GROUP).also { it.load() }
        assertEquals("Пока никто не прочитал", empty.state.value.emptyText)
    }

    @Test
    fun groupWithoutServerListHidesTheBlockAndFailureOffersRetry() {
        assertEquals(MessageInfoState.Phase.Unavailable, model(ChatType.GROUP, repo = Readers { null }).also { it.load() }.state.value.phase)
        assertEquals(MessageInfoState.Phase.Failed, model(ChatType.GROUP, repo = Readers { error("сеть") }).also { it.load() }.state.value.phase)
        assertEquals(MessageInfoState.Phase.Unavailable, model(ChatType.CHANNEL).also { it.load() }.state.value.phase)
    }

    @Test
    fun savedMessagesAndUnsentMessagesHaveNoStatusOrReaders() {
        val repo = Readers { error("не спрашивать") }
        val saved = MessageInfoModel("0", message(isRead = true), ChatType.PRIVATE, true, repo, TestScope(UnconfinedTestDispatcher()), zone)
        assertNull(saved.delivery)
        assertEquals(1, saved.rows.size)
        val sending = message(status = MessageStatus.SENDING).copy(id = "local-1")
        assertNull(model(ChatType.PRIVATE, sending, repo = repo).delivery)
        assertEquals(false, MessageInfoModel.isOffered(sending))
        assertEquals(false, MessageInfoModel.isOffered(message(status = MessageStatus.FAILED).copy(id = "local-1")))
        assertEquals(true, MessageInfoModel.isOffered(message()))
        val group = model(ChatType.GROUP, sending, repo = repo).also { it.load() }
        assertEquals(false, group.showsReaders)
        assertEquals(MessageInfoState.Phase.Unavailable, group.state.value.phase)
        assertEquals(0, repo.asked)
    }

    @Test
    fun readerLineShowsReadMarkOnlyWhenKnown() {
        val info = model(ChatType.GROUP)
        assertEquals("Прочитано · 8 октября 2026, 16:44", info.readText(MessageReader("2", "Пётр", readMarkMs = sent)))
        assertNull(info.readText(MessageReader("3", "Анна", emoji = "👍")))
    }

    private companion object {
        fun unused(): MessageRepository = Proxy.newProxyInstance(
            MessageRepository::class.java.classLoader,
            arrayOf(MessageRepository::class.java),
        ) { _, method, _ -> error("не нужен: ${method.name}") } as MessageRepository
    }
}
