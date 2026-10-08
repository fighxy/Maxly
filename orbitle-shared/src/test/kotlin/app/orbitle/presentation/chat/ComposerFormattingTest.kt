package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatMemberRow
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.TextSpan
import app.orbitle.domain.TextSpan.Kind.EMPHASIZED
import app.orbitle.domain.TextSpan.Kind.LINK
import app.orbitle.domain.TextSpan.Kind.MENTION
import app.orbitle.domain.TextSpan.Kind.STRONG
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class ComposerFormattingTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeMessages()
    private val now = 1_790_683_200_000L

    private fun vm() = ChatViewModel("10", repo, ChatFormatter(ZoneOffset.UTC), now = { now })

    private fun own(id: String, text: String, formatting: List<TextSpan> = emptyList()) =
        Message(id = id, chatId = "10", authorId = "1", text = text, timeMs = now, content = MessageContent(formatting = formatting))

    @Test
    fun toggleShowsInStateAndTypingMovesIt() {
        val model = vm()
        model.setDraft("hello world", cursor = 11)
        model.toggleFormat(STRONG, 6, 11)
        assertEquals(listOf(TextSpan(STRONG, 6, 5)), model.state.value.formatting)
        model.setDraft("oh hello world", cursor = 3)
        assertEquals(listOf(TextSpan(STRONG, 9, 5)), model.state.value.formatting)
        // Повторное нажатие снимает.
        model.toggleFormat(STRONG, 9, 14)
        assertTrue(model.state.value.formatting.isEmpty())
    }

    @Test
    fun selectionIsClampedAndEmptyOneIgnored() {
        val model = vm()
        model.setDraft("abc")
        model.toggleFormat(EMPHASIZED, 2, 2)
        assertTrue(model.state.value.formatting.isEmpty())
        // Выделение справа налево и за концом текста.
        model.toggleFormat(EMPHASIZED, 10, 1)
        assertEquals(listOf(TextSpan(EMPHASIZED, 1, 2)), model.state.value.formatting)
        // Упоминание кнопкой не ставится.
        model.toggleFormat(MENTION, 0, 1)
        assertEquals(listOf(TextSpan(EMPHASIZED, 1, 2)), model.state.value.formatting)
    }

    @Test
    fun sendsFormattingTrimmedTogetherWithMentions() {
        val model = vm()
        model.setDraft("  привет @")
        model.insertMention(ChatMemberRow("7", "Анна"))
        val draft = model.state.value.draft
        assertEquals("  привет @Анна ", draft)
        // Жирным — всё «привет @Анна», упоминание внутри жирного.
        model.toggleFormat(STRONG, 2, 14)
        model.send()
        assertEquals("привет @Анна", repo.sent.single().first)
        assertEquals(
            listOf(TextSpan(STRONG, 0, 12), TextSpan(MENTION, 7, 5, userId = "7")),
            repo.formatted.single(),
        )
        assertTrue(model.state.value.formatting.isEmpty())
        assertEquals("", model.state.value.draft)
    }

    @Test
    fun plainTextStillUsesPlainSend() {
        val model = vm()
        model.setDraft("просто")
        model.send()
        assertEquals("просто", repo.sent.single().first)
        assertTrue(repo.formatted.isEmpty())
    }

    @Test
    fun clearingTheFieldDropsFormatting() {
        val model = vm()
        model.setDraft("abc")
        model.toggleFormat(STRONG, 0, 3)
        model.setDraft("")
        assertTrue(model.state.value.formatting.isEmpty())
        model.setDraft("abc")
        assertTrue(model.state.value.formatting.isEmpty())
    }

    @Test
    fun linkIsNormalizedAndRemovable() {
        val model = vm()
        model.setDraft("сайт тут")
        model.setLink(5, 8, "max.ru")
        assertEquals(listOf(TextSpan(LINK, 5, 3, url = "https://max.ru")), model.state.value.formatting)
        assertEquals("https://max.ru", model.linkAt(5, 8))
        model.setLink(5, 8, "плохой адрес")
        assertEquals("Ссылка не похожа на адрес", model.messages.value)
        assertEquals("https://max.ru", model.linkAt(5, 8))
        model.setLink(5, 8, null)
        assertTrue(model.state.value.formatting.isEmpty())
    }

    @Test
    fun editPrefillsFormattingAndMentionsAndSendsThemBack() {
        val model = vm()
        model.setDraft("черновик")
        model.toggleFormat(EMPHASIZED, 0, 8)
        val message = own("5", "жирный @Анна", listOf(TextSpan(STRONG, 0, 6), TextSpan(MENTION, 7, 5, userId = "7")))
        model.beginEdit(message)
        assertEquals("жирный @Анна", model.state.value.draft)
        assertEquals(listOf(TextSpan(STRONG, 0, 6)), model.state.value.formatting)
        model.setDraft("жирный @Анна!", cursor = 13)
        model.send()
        assertEquals(
            Triple("5", "жирный @Анна!", listOf(TextSpan(STRONG, 0, 6), TextSpan(MENTION, 7, 5, userId = "7"))),
            repo.formattedEdits.single(),
        )
        // Черновик до правки вернулся вместе со своей разметкой.
        assertEquals("черновик", model.state.value.draft)
        assertEquals(listOf(TextSpan(EMPHASIZED, 0, 8)), model.state.value.formatting)
    }

    @Test
    fun formattingOnlyEditIsSentButAnUntouchedOneIsNot() {
        val model = vm()
        val message = own("5", "текст", listOf(TextSpan(STRONG, 0, 5)))
        model.beginEdit(message)
        model.send()
        assertTrue(repo.formattedEdits.isEmpty())
        model.beginEdit(message)
        model.toggleFormat(STRONG, 0, 5)
        model.send()
        assertEquals(Triple("5", "текст", emptyList<TextSpan>()), repo.formattedEdits.single())
    }

    @Test
    fun cancelEditRestoresTheDraftFormatting() {
        val model = vm()
        model.setDraft("моё")
        model.toggleFormat(STRONG, 0, 3)
        model.beginEdit(own("5", "чужая разметка", listOf(TextSpan(EMPHASIZED, 0, 5))))
        assertEquals(listOf(TextSpan(EMPHASIZED, 0, 5)), model.state.value.formatting)
        model.cancelEdit()
        assertEquals("моё", model.state.value.draft)
        assertEquals(listOf(TextSpan(STRONG, 0, 3)), model.state.value.formatting)
    }

    @Test
    fun draftMentionsSurviveAnEdit() {
        val model = vm()
        model.setDraft("@")
        model.insertMention(ChatMemberRow("7", "Анна"))
        model.beginEdit(own("5", "текст"))
        model.cancelEdit()
        assertEquals("@Анна ", model.state.value.draft)
        model.send()
        assertEquals(listOf(TextSpan(MENTION, 0, 5, userId = "7")), repo.formatted.single())
    }

    @Test
    fun failedEditReturnsWithItsFormatting() {
        val model = vm()
        repo.editFailure = OrbitleError.Rejected("Не вышло")
        model.beginEdit(own("5", "текст"))
        model.toggleFormat(STRONG, 0, 5)
        model.send()
        assertEquals("текст", model.state.value.draft)
        assertEquals(listOf(TextSpan(STRONG, 0, 5)), model.state.value.formatting)
        assertEquals("Не вышло", model.messages.value)
    }
}
