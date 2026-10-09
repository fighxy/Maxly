package app.maxly.data

import app.maxly.domain.TextSpan
import com.max.core.api.TextElement
import com.max.core.api.TextElementType
import org.junit.Assert.assertEquals
import org.junit.Test

class TextMarksTest {
    @Test
    fun everyKindBecomesTheCoreElement() {
        val text = "жирный курсив ссылка код @анна 🔥"
        val spans = listOf(
            TextSpan(TextSpan.Kind.STRONG, 0, 6),
            TextSpan(TextSpan.Kind.EMPHASIZED, 7, 6),
            TextSpan(TextSpan.Kind.LINK, 14, 6, url = "https://max.ru"),
            TextSpan(TextSpan.Kind.MONOSPACED, 21, 3),
            TextSpan(TextSpan.Kind.MENTION, 25, 5, userId = "12"),
            TextSpan(TextSpan.Kind.ANIMOJI, 31, 2, url = "https://cdn/a.json", entityId = "7"),
        )
        val elements = TextMarks.toElements(text, spans)
        assertEquals(
            listOf(
                TextElement.strong(0, 6),
                TextElement.emphasized(7, 6),
                TextElement.link(14, 6, "https://max.ru"),
                TextElement.monospaced(21, 3),
                TextElement.mention(25, 5, 12L),
                TextElement.animoji(31, 2, 7L, "https://cdn/a.json"),
            ),
            elements,
        )
        // Обратно — те же отметки (так читаются черновики с сервера).
        assertEquals(spans, TextMarks.fromElements(elements))
        // И та же схема, что разбирает чтение входящих сообщений.
        assertEquals(spans, MessageMapping.spans(TextElement.payloadFor(text, elements)))
    }

    @Test
    fun elementsGoInTextOrder() {
        val elements = TextMarks.toElements(
            "привет мир",
            listOf(TextSpan(TextSpan.Kind.UNDERLINE, 7, 3), TextSpan(TextSpan.Kind.QUOTE, 0, 10), TextSpan(TextSpan.Kind.STRONG, 2, 2)),
        )
        assertEquals(listOf(0, 2, 7), elements.map { it.from })
    }

    @Test
    fun brokenRangesBareLinksAndBadIdsAreSkipped() {
        val elements = TextMarks.toElements(
            "привет",
            listOf(
                TextSpan(TextSpan.Kind.MENTION, 0, 3, userId = "no"),
                TextSpan(TextSpan.Kind.ANIMOJI, 0, 1),
                TextSpan(TextSpan.Kind.STRONG, 4, 5),
                TextSpan(TextSpan.Kind.STRONG, -1, 2),
                TextSpan(TextSpan.Kind.EMPHASIZED, 2, 0),
                TextSpan(TextSpan.Kind.LINK, 0, 3),
                TextSpan(TextSpan.Kind.MENTION, 8, 1, userId = "3"),
                TextSpan(TextSpan.Kind.QUOTE, 0, 6),
            ),
        )
        assertEquals(listOf(TextElement.quote(0, 6)), elements)
    }

    @Test
    fun codeReadsAsMonospaceAndUnknownTypesAreKept() {
        val spans = TextMarks.fromElements(
            listOf(
                TextElement(TextElementType.CODE, 0, 3),
                TextElement("Spoiler", 0, 3, entityId = 7, attributes = mapOf("level" to 2)),
                TextElement(TextElementType.LINK, 0, 3),
                TextElement(TextElementType.USER_MENTION, 0, 3),
            ),
        )
        assertEquals(
            listOf(
                TextSpan(TextSpan.Kind.MONOSPACED, 0, 3),
                TextSpan(TextSpan.Kind.UNKNOWN, 0, 3, foreign = TextElement("Spoiler", 0, 0, entityId = 7, attributes = mapOf("level" to 2))),
            ),
            spans,
        )
    }

    @Test
    fun unknownTypeKeepsEveryKeyOfTheReceivedElement() {
        val received = TextElement.parse(mapOf("type" to "Spoiler", "from" to 0L, "length" to 6L, "style" to mapOf("blur" to 3L), "rev" to 2L), 6)!!
        val span = TextMarks.fromElements(listOf(received), 6).single()
        val sent = TextMarks.toElements("abc hidden", listOf(span.copy(from = 4))).single().toPayload()
        assertEquals(mapOf("type" to "Spoiler", "from" to 4, "length" to 6, "style" to mapOf("blur" to 3L), "rev" to 2L), sent)
    }

    @Test
    fun unknownTypeGoesBackOnEditWithItsKeysAtTheNewOffsets() {
        val foreign = TextElement("Spoiler", 0, 0, entityId = 7, entityName = "x", attributes = mapOf("level" to 2))
        val elements = TextMarks.toElements("ab hidden", listOf(TextSpan(TextSpan.Kind.UNKNOWN, 3, 6, foreign = foreign)))
        assertEquals(listOf(foreign.copy(from = 3, length = 6)), elements)
    }
}
