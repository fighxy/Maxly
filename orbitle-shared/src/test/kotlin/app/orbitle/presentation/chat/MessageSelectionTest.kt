package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageForward
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PhotoContent
import app.orbitle.presentation.common.PresenceText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class MessageSelectionTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val now = 1_790_683_200_000L // 2026-09-29 12:00 UTC
    private val minute = 60_000L

    private fun vm(chatId: String = "10") = ChatViewModel(chatId, repo, ChatFormatter(ZoneOffset.UTC), now = { now })

    private fun msg(
        id: String,
        author: String = "2",
        at: Long = now,
        text: String = "т$id",
        status: MessageStatus = MessageStatus.SENT,
        name: String = "Анна",
        content: MessageContent = MessageContent.empty,
        service: Boolean = false,
    ) = Message(id = id, chatId = "10", authorId = author, text = text, timeMs = at, status = status, authorName = name, content = content, isService = service)

    // Подписи

    @Test
    fun russianPluralForms() {
        assertEquals("1 сообщение", MessageSelection.countLabel(1))
        assertEquals("2 сообщения", MessageSelection.countLabel(2))
        assertEquals("4 сообщения", MessageSelection.countLabel(4))
        assertEquals("5 сообщений", MessageSelection.countLabel(5))
        assertEquals("11 сообщений", MessageSelection.countLabel(11))
        assertEquals("12 сообщений", MessageSelection.countLabel(12))
        assertEquals("14 сообщений", MessageSelection.countLabel(14))
        assertEquals("21 сообщение", MessageSelection.countLabel(21))
        assertEquals("22 сообщения", MessageSelection.countLabel(22))
        assertEquals("25 сообщений", MessageSelection.countLabel(25))
        assertEquals("100 сообщений", MessageSelection.countLabel(100))
        assertEquals("101 сообщение", MessageSelection.countLabel(101))
        assertEquals("111 сообщений", MessageSelection.countLabel(111))
        assertEquals("112 сообщений", MessageSelection.countLabel(112))
        assertEquals("1001 сообщение", MessageSelection.countLabel(1001))
        assertEquals("0 сообщений", MessageSelection.countLabel(0))
        // Общий помощник и для других слов.
        assertEquals("участника", PresenceText.plural(3, "участник", "участника", "участников"))
    }

    @Test
    fun titlesAndNotices() {
        assertEquals("3 сообщения", MessageSelection.title(3))
        assertEquals("Удалить сообщение?", MessageSelection.deleteTitle(1))
        assertEquals("Удалить 5 сообщений?", MessageSelection.deleteTitle(5))
        assertEquals("Сообщение переслано", MessageSelection.forwardedNotice(1))
        assertEquals("Переслано: 2 сообщения", MessageSelection.forwardedNotice(2))
    }

    // Текст для копирования

    private val clock: (Long) -> String = { ChatFormatter(ZoneOffset.UTC).time(it) }

    @Test
    fun singleMessageCopiesJustItsText() {
        assertEquals("привет", MessageSelection.copyText(listOf(msg("1", text = "  привет ")), clock) { it.authorName })
        assertEquals("", MessageSelection.copyText(emptyList(), clock) { it.authorName })
    }

    @Test
    fun severalMessagesBecomeATranscriptOldestFirst() {
        val first = msg("1", at = now, text = "привет", name = "Анна")
        val second = msg("2", author = "1", at = now + minute, text = "как дела?", name = "Иван")
        val third = msg("3", at = now + 65 * minute, text = "хорошо\nа у тебя?", name = "Анна")
        // Порядок выбора не важен: копия идёт по времени.
        val text = MessageSelection.copyText(listOf(third, first, second), clock) { it.authorName }
        assertEquals(
            "Анна, 12:00\nпривет\n\nИван, 12:01\nкак дела?\n\nАнна, 13:05\nхорошо\nа у тебя?",
            text,
        )
    }

    @Test
    fun sameTimeKeepsServerOrder() {
        val a = msg("100", text = "a")
        val b = msg("99", text = "b")
        assertEquals("Анна, 12:00\nb\n\nАнна, 12:00\na", MessageSelection.copyText(listOf(a, b), clock) { it.authorName })
    }

    @Test
    fun messagesWithoutTextGetAPlaceholderAndForwardsTheirOriginal() {
        val photo = msg("1", text = "", content = MessageContent(attachments = listOf(ChatAttachment.Photo(PhotoContent("p", null)))))
        val forwarded = msg("2", at = now + minute, text = "", content = MessageContent(forward = MessageForward("Борис", "новость")))
        assertEquals(
            "Анна, 12:00\n[Фото]\n\nАнна, 12:01\nновость",
            MessageSelection.copyText(listOf(photo, forwarded), clock) { it.authorName },
        )
    }

    // Модель чата

    @Test
    fun onlyServerMessagesCanBeSelected() {
        val model = vm()
        assertTrue(model.canSelect(msg("5")))
        assertFalse(model.canSelect(msg("6", service = true)))
        assertFalse(model.canSelect(msg("local-1", author = "1", status = MessageStatus.SENDING)))
        assertFalse(model.canSelect(msg("local-2", author = "1", status = MessageStatus.FAILED)))
        // Числовой id, но ещё не подтверждён сервером.
        assertFalse(model.canSelect(msg("7", status = MessageStatus.SENDING)))
    }

    @Test
    fun selectionTogglesAndEndsWithTheLastOne() {
        val a = msg("1")
        val b = msg("2", at = now + minute)
        repo.list.value = listOf(a, b)
        val model = vm()
        assertFalse(model.isSelecting)
        model.startSelection(a)
        assertTrue(model.isSelecting)
        assertEquals(setOf("1"), model.selection.value)
        model.toggleSelection(b)
        assertEquals(setOf("1", "2"), model.selection.value)
        model.toggleSelection(a)
        assertEquals(setOf("2"), model.selection.value)
        model.toggleSelection(b)
        assertTrue(model.selection.value.isEmpty())
        assertFalse(model.isSelecting)
    }

    @Test
    fun unselectableMessagesAreIgnored() {
        val service = msg("3", service = true)
        val pending = msg("local-1", author = "1", status = MessageStatus.SENDING)
        repo.list.value = listOf(msg("1"), service, pending)
        val model = vm()
        model.startSelection(service)
        model.toggleSelection(pending)
        assertTrue(model.selection.value.isEmpty())
        model.startSelection(msg("1"))
        model.toggleSelection(service)
        assertEquals(setOf("1"), model.selection.value)
    }

    @Test
    fun clearSelectionExitsTheMode() {
        repo.list.value = listOf(msg("1"), msg("2"))
        val model = vm()
        model.startSelection(msg("1"))
        model.toggleSelection(msg("2"))
        model.clearSelection()
        assertTrue(model.selection.value.isEmpty())
    }

    @Test
    fun messagesThatDisappearLeaveTheSelection() {
        repo.list.value = listOf(msg("1"), msg("2"), msg("3"))
        val model = vm()
        model.startSelection(msg("1"))
        model.toggleSelection(msg("3"))
        // Сообщение удалили на другом устройстве.
        repo.list.value = listOf(msg("1"), msg("2"))
        assertEquals(setOf("1"), model.selection.value)
        repo.list.value = listOf(msg("2"))
        assertTrue(model.selection.value.isEmpty())
    }

    @Test
    fun copiesSelectionInChronologicalOrderWithNames() {
        repo.headerInfo.value = ChatHeaderInfo(Chat(id = "10", title = "Анна", type = ChatType.PRIVATE, updatedAtMs = now))
        val mine = msg("2", author = "1", at = now + minute, text = "ответ", name = "")
        val theirs = msg("1", text = "вопрос", name = "")
        repo.list.value = listOf(theirs, mine)
        val model = vm()
        model.startSelection(mine)
        assertEquals("ответ", model.selectionText())
        model.toggleSelection(theirs)
        // Без имени автора: своё — «Вы», в личном чате чужое — название чата.
        assertEquals("Анна, 12:00\nвопрос\n\nВы, 12:01\nответ", model.selectionText())
    }

    @Test
    fun deleteSelectionUsesOneRequestAndExits() {
        val own1 = msg("1", author = "1")
        val own2 = msg("2", author = "1", at = now + minute)
        val foreign = msg("3", at = now + 2 * minute)
        repo.list.value = listOf(own1, own2, foreign)
        val model = vm()
        model.startSelection(own2)
        model.toggleSelection(own1)
        assertTrue(model.canDeleteSelectionForEveryone())
        model.toggleSelection(foreign)
        // Чужое нельзя удалить у всех — значит, и всю выборку.
        assertFalse(model.canDeleteSelectionForEveryone())
        model.deleteSelection(forEveryone = false)
        assertEquals(listOf(listOf("1", "2", "3") to false), repo.deletes)
        assertTrue(model.selection.value.isEmpty())
    }

    @Test
    fun deleteSelectionForEveryone() {
        repo.list.value = listOf(msg("1", author = "1"), msg("2", author = "1"))
        val model = vm()
        model.startSelection(msg("1", author = "1"))
        model.toggleSelection(msg("2", author = "1"))
        model.deleteSelection(forEveryone = true)
        assertEquals(listOf(listOf("1", "2") to true), repo.deletes)
    }

    @Test
    fun savedMessagesDeleteWithoutChoice() {
        repo.list.value = listOf(msg("1", author = "1"), msg("2", author = "1"))
        val model = vm(Chat.SAVED_MESSAGES_ID)
        model.startSelection(msg("1", author = "1"))
        model.toggleSelection(msg("2", author = "1"))
        assertFalse(model.canDeleteSelectionForEveryone())
        model.deleteSelection(forEveryone = false)
        assertEquals(listOf(listOf("1", "2") to true), repo.deletes)
    }

    @Test
    fun deletingSelectionDropsReplyToIt() {
        val target = msg("1")
        repo.list.value = listOf(target, msg("2"))
        val model = vm()
        model.beginReply(target)
        model.startSelection(target)
        model.deleteSelection(forEveryone = false)
        assertEquals(null, model.state.value.replyTo)
    }

    @Test
    fun forwardSelectionGoesOneByOneOldestFirst() {
        val a = msg("5", at = now)
        val b = msg("7", at = now + minute)
        val c = msg("6", at = now + 2 * minute)
        repo.list.value = listOf(a, b, c)
        val model = vm()
        model.startSelection(c)
        model.toggleSelection(a)
        model.toggleSelection(b)
        model.forwardSelection("20")
        assertEquals(listOf(Triple("10", "5", "20"), Triple("10", "7", "20"), Triple("10", "6", "20")), repo.forwards)
        assertEquals("Переслано: 3 сообщения", model.messages.value)
        assertTrue(model.selection.value.isEmpty())
    }

    @Test
    fun forwardFailureSaysHowManyWent() {
        repo.list.value = listOf(msg("1"), msg("2", at = now + minute))
        val model = vm()
        model.startSelection(msg("1"))
        model.toggleSelection(msg("2"))
        repo.forwardFailure = OrbitleError.Rejected("Нельзя переслать")
        model.forwardSelection("20")
        assertEquals("Нельзя переслать", model.messages.value)
        assertTrue(repo.forwards.isEmpty())
        assertTrue(model.selection.value.isEmpty())
    }

    @Test
    fun deleteOfSeveralDiscardsLocalOnesAndSendsTheRest() {
        val failed = msg("local-1", author = "1", status = MessageStatus.FAILED)
        repo.list.value = listOf(msg("1", author = "1"), failed)
        val model = vm()
        model.delete(listOf(msg("1", author = "1"), failed), forEveryone = true)
        assertEquals(listOf(listOf("1") to true), repo.deletes)
        assertEquals(listOf("1"), repo.list.value.map { it.id })
    }
}
