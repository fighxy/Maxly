package app.maxly.data

import app.maxly.domain.ChatDraft
import app.maxly.domain.TextSpan
import com.max.core.api.MaxDraft
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
    fun replyWithoutTextIsADraft() {
        val draft = ChatDraft("", 1_790_000_000_000L, replyTo = "77")
        assertEquals(draft, DraftCodec.decode(DraftCodec.encode(draft)))
        assertNull(DraftCodec.decode(DraftCodec.encode(ChatDraft("  ", 1))))
    }

    @Test
    fun coreDraftWithOnlyAReplyIsKept() {
        val reply = CoreDraftRepository.draft(MaxDraft(10, "", emptyList(), 77, 500))
        assertEquals(ChatDraft("", 500, emptyList(), "77"), reply)
        assertEquals(true, reply?.isEmpty?.not())
        assertNull(CoreDraftRepository.draft(MaxDraft(10, " ", emptyList(), null, 500)))
        assertEquals(ChatDraft("текст", 600), CoreDraftRepository.draft(MaxDraft(10, "текст", emptyList(), null, 600)))
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
