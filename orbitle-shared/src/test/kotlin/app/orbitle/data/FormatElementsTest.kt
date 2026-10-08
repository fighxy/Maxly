package app.orbitle.data

import app.orbitle.domain.TextSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FormatElementsTest {
    @Test
    fun formatKindsUseTheNamesTheReaderAccepts() {
        val text = "жирный курсив ссылка код"
        val spans = listOf(
            TextSpan(TextSpan.Kind.STRONG, 0, 6),
            TextSpan(TextSpan.Kind.EMPHASIZED, 7, 6),
            TextSpan(TextSpan.Kind.LINK, 14, 6, url = "https://max.ru"),
            TextSpan(TextSpan.Kind.MONOSPACED, 21, 3),
            TextSpan(TextSpan.Kind.UNDERLINE, 0, 2),
            TextSpan(TextSpan.Kind.STRIKETHROUGH, 3, 2),
        )
        val elements = LockPayloads.formatElements(text, spans)
        assertEquals(listOf("STRONG", "EMPHASIZED", "LINK", "MONOSPACED", "UNDERLINE", "STRIKETHROUGH"), elements.map { it["type"] })
        assertEquals(linkedMapOf<String, Any?>("type" to "STRONG", "from" to 0, "length" to 6), elements[0])
        assertEquals(mapOf("url" to "https://max.ru"), elements[2]["attributes"])
        // Что уходит, то и читается обратно той же разборкой, что у входящих сообщений.
        assertEquals(spans, MessageMapping.spans(elements))
    }

    @Test
    fun mentionsAnimojiBrokenRangesAndBareLinksAreSkipped() {
        val text = "привет"
        val elements = LockPayloads.formatElements(
            text,
            listOf(
                TextSpan(TextSpan.Kind.MENTION, 0, 3, userId = "5"),
                TextSpan(TextSpan.Kind.ANIMOJI, 0, 1, entityId = "7"),
                TextSpan(TextSpan.Kind.STRONG, 4, 5),
                TextSpan(TextSpan.Kind.STRONG, -1, 2),
                TextSpan(TextSpan.Kind.EMPHASIZED, 2, 0),
                TextSpan(TextSpan.Kind.LINK, 0, 3),
                TextSpan(TextSpan.Kind.QUOTE, 0, 6),
            ),
        )
        assertEquals(listOf("QUOTE"), elements.map { it["type"] })
        assertTrue(elements.none { it.containsKey("attributes") })
    }
}
