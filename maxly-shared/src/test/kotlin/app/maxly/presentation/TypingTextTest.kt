package app.maxly.presentation

import app.maxly.domain.ChatType
import app.maxly.domain.Typist
import app.maxly.domain.TypingKind
import app.maxly.presentation.common.TypingText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TypingTextTest {
    private fun t(name: String?, kind: TypingKind = TypingKind.TEXT, since: Long = 0) = Typist(name, kind, since)

    @Test
    fun kindsFromProtocol() {
        assertEquals(TypingKind.VIDEO_MSG, TypingKind.of("VIDEO_MSG"))
        assertEquals(TypingKind.TEXT, TypingKind.of(null))
        assertEquals(TypingKind.TEXT, TypingKind.of("SOMETHING_NEW"))
    }

    @Test
    fun privateAndChannel() {
        assertEquals("печатает…", TypingText.of(listOf(t("Иван")), ChatType.PRIVATE))
        assertEquals("записывает аудио…", TypingText.of(listOf(t("Иван", TypingKind.AUDIO)), ChatType.PRIVATE))
        assertEquals("выбирает стикер…", TypingText.of(listOf(t(null, TypingKind.STICKER)), ChatType.PRIVATE))
        assertNull(TypingText.of(listOf(t("Иван")), ChatType.CHANNEL))
        assertNull(TypingText.of(emptyList(), ChatType.GROUP))
    }

    @Test
    fun groupNames() {
        assertEquals("Иван печатает…", TypingText.of(listOf(t("Иван")), ChatType.GROUP))
        assertEquals("Иван и Петя печатают…", TypingText.of(listOf(t("Иван", since = 1), t("Петя", since = 2)), ChatType.GROUP))
        assertEquals(
            "Иван, Петя и Маша записывают видеосообщение…",
            TypingText.of(listOf(t("Иван", TypingKind.VIDEO_MSG, 1), t("Петя", TypingKind.VIDEO_MSG, 2), t("Маша", TypingKind.VIDEO_MSG, 3)), ChatType.GROUP),
        )
        assertEquals(
            "Иван и ещё 3 отправляют фото…",
            TypingText.of((1..4).map { t(listOf("Иван", "Петя", "Маша", "Оля")[it - 1], TypingKind.PHOTO, it.toLong()) }, ChatType.GROUP),
        )
    }

    @Test
    fun groupTakesKindOfEarliestAndOnlyThosePeople() {
        val typists = listOf(t("Петя", TypingKind.TEXT, 5), t("Иван", TypingKind.AUDIO, 1), t("Маша", TypingKind.AUDIO, 3))
        assertEquals("Иван и Маша записывают аудио…", TypingText.of(typists, ChatType.GROUP))
    }

    @Test
    fun groupWithoutNamesFallsBackToCount() {
        assertEquals("2 участника отправляют файл…", TypingText.of(listOf(t("Иван", TypingKind.FILE), t(null, TypingKind.FILE)), ChatType.GROUP))
        assertEquals("21 участник печатает…", TypingText.counted(21))
        assertEquals("11 участников печатают…", TypingText.counted(11))
        assertEquals("отправляет видео…", TypingText.counted(1, TypingKind.VIDEO))
    }
}
