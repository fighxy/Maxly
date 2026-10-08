package app.orbitle.data

import app.orbitle.domain.ChatDraft
import app.orbitle.domain.TextSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DraftCodecTest {
    @Test
    fun draftWithMarksReplyAndTabsSurvives() {
        val draft = ChatDraft(
            text = "жирный\tи @анна",
            updatedAtMs = 1_790_000_000_000L,
            formatting = listOf(
                TextSpan(TextSpan.Kind.STRONG, 0, 6),
                TextSpan(TextSpan.Kind.MENTION, 9, 5, userId = "12"),
                TextSpan(TextSpan.Kind.LINK, 7, 1, url = "https://max.ru"),
            ),
            replyTo = "77",
        )
        val back = DraftCodec.decode(DraftCodec.encode(draft))!!
        assertEquals(draft.text, back.text)
        assertEquals(draft.updatedAtMs, back.updatedAtMs)
        assertEquals("77", back.replyTo)
        assertEquals(draft.formatting.toSet(), back.formatting.toSet())
    }

    @Test
    fun oldRecordsReadAsPlainText() {
        assertEquals(ChatDraft("старый\tчерновик", 42L), DraftCodec.decode("42\tстарый\tчерновик"))
        assertNull(DraftCodec.decode("42\t  "))
        assertNull(DraftCodec.decode(DraftCodec.encode(ChatDraft(" ", 1))))
    }

    @Test
    fun brokenMarksDoNotLoseTheText() {
        val draft = DraftCodec.decode("v2\t5\t\tне json\tтекст")!!
        assertEquals("текст", draft.text)
        assertEquals(emptyList<TextSpan>(), draft.formatting)
        assertNull(draft.replyTo)
    }
}
