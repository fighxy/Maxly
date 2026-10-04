package app.orbitle.presentation.chat

import app.orbitle.presentation.common.PresenceText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class ChatContentFormatTest {
    @Test
    fun waveBars() {
        val calm = ChatContentFormat.waveBars(emptyList())
        assertEquals(28, calm.size)
        assertTrue(calm.all { it in 0.12..1.0 })
        assertEquals(1.0, calm.max(), 0.0)
        val bars = ChatContentFormat.waveBars(listOf(10, 200, 40), count = 3)
        assertEquals(listOf(0.12, 1.0, 0.2), bars)
        val stretched = ChatContentFormat.waveBars(listOf(0, 100), count = 5)
        assertEquals(listOf(0.12, 0.25, 0.5, 0.75, 1.0), stretched)
    }

    @Test
    fun bigEmojiIsOneToThreeSymbols() {
        assertEquals(listOf("🔥"), ChatContentFormat.bigEmoji("🔥"))
        assertEquals(listOf("👍🏽", "❤️"), ChatContentFormat.bigEmoji(" 👍🏽 ❤️ "))
        assertEquals(listOf("🇷🇺"), ChatContentFormat.bigEmoji("🇷🇺"))
        assertNull(ChatContentFormat.bigEmoji("🔥🔥🔥🔥"))
        assertNull(ChatContentFormat.bigEmoji("ok 🔥"))
        assertNull(ChatContentFormat.bigEmoji("1"))
        assertNull(ChatContentFormat.bigEmoji(""))
        assertEquals(64, ChatContentFormat.bigEmojiSize(1))
        assertEquals(52, ChatContentFormat.bigEmojiSize(2))
        assertEquals(44, ChatContentFormat.bigEmojiSize(3))
    }

    @Test
    fun fileSize() {
        assertEquals("0 Б", ChatContentFormat.fileSize(0))
        assertEquals("1023 Б", ChatContentFormat.fileSize(1023))
        assertEquals("1 КБ", ChatContentFormat.fileSize(1024))
        assertEquals("1,5 КБ", ChatContentFormat.fileSize(1536))
        assertEquals("5 МБ", ChatContentFormat.fileSize(5L * 1024 * 1024))
        assertEquals("0 Б", ChatContentFormat.fileSize(-4))
    }

    @Test
    fun frameKeepsRatioWithinLimits() {
        assertEquals(ChatContentFormat.Frame(300.0, 300.0), ChatContentFormat.frame(null, null, 300.0))
        val wide = ChatContentFormat.frame(4000, 100, 300.0)
        assertEquals(300.0 / 1.91, wide.height, 0.001)
        val tall = ChatContentFormat.frame(100, 4000, 300.0)
        assertEquals(420.0, tall.height, 0.0)
        assertEquals(420.0 * 0.45, tall.width, 0.001)
    }

    @Test
    fun waveformLayout() {
        val layout = WaveformLayout.of(100.0, barWidth = 3.0, spacing = 2.0)
        assertEquals(20, layout.count)
        assertEquals(0.0, layout.x(0), 0.0)
        assertEquals(97.0, layout.x(19), 0.001)
        assertFalse(layout.isPlayed(0, 0.0))
        assertTrue(layout.isPlayed(19, 1.0))
        assertTrue(layout.isPlayed(0, 0.02))
        assertEquals(1.0, layout.progressAt(150.0), 0.0)
        assertEquals(0.0, layout.progressAt(-5.0), 0.0)
    }

    private val zone = ZoneId.of("Asia/Novosibirsk")
    private fun ms(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0) =
        LocalDateTime.of(y, m, d, h, min).atZone(zone).toInstant().toEpochMilli()

    @Test
    fun dayLabels() {
        val formatter = ChatFormatter(zone)
        val now = ms(2026, 10, 2, 18)
        assertEquals("Сегодня", formatter.dayLabel(ms(2026, 10, 2, 0, 5), now))
        assertEquals("Вчера", formatter.dayLabel(ms(2026, 10, 1, 23), now))
        assertEquals("5 марта", formatter.dayLabel(ms(2026, 3, 5), now))
        assertEquals("31 декабря 2025", formatter.dayLabel(ms(2025, 12, 31), now))
        assertEquals("09:07", formatter.time(ms(2026, 10, 2, 9, 7)))
    }

    @Test
    fun presence() {
        val text = PresenceText(zone)
        val now = ms(2026, 10, 2, 18)
        assertEquals("в сети", text.status(true, 0, now))
        assertEquals("был(а) недавно", text.status(false, 0, now))
        assertEquals("был(а) только что", text.status(false, now - 30_000, now))
        assertEquals("был(а) 5 минут назад", text.status(false, now - 5 * 60_000, now))
        assertEquals("был(а) 1 минуту назад", text.status(false, now - 61_000, now))
        assertEquals("был(а) в 09:30", text.status(false, ms(2026, 10, 2, 9, 30), now))
        assertEquals("был(а) вчера в 22:00", text.status(false, ms(2026, 10, 1, 22), now))
        assertEquals("был(а) 5 марта", text.status(false, ms(2026, 3, 5), now))
        assertEquals("был(а) 05.03.2024", text.status(false, ms(2024, 3, 5), now))
    }

    @Test
    fun pluralAndGrouping() {
        assertEquals("участник", PresenceText.plural(1, "участник", "участника", "участников"))
        assertEquals("участника", PresenceText.plural(3, "участник", "участника", "участников"))
        assertEquals("участников", PresenceText.plural(11, "участник", "участника", "участников"))
        assertEquals("участник", PresenceText.plural(21, "участник", "участника", "участников"))
        assertEquals("1500", PresenceText.grouped(1500))
        assertEquals("12\u202F500", PresenceText.grouped(12500))
        assertEquals("1\u202F234\u202F567", PresenceText.grouped(1234567))
    }

    @Test
    fun reactionPalette() {
        assertEquals(ReactionPalette.FALLBACK, ReactionPalette.quick(emptyList()))
        val catalog = listOf("1", "2", "3", "4", "5", "6", "7")
        assertEquals(listOf("1", "2", "3", "4", "5", "6"), ReactionPalette.quick(catalog, mine = "3"))
        assertEquals(listOf("7", "1", "2", "3", "4", "5"), ReactionPalette.quick(catalog, mine = "7"))
    }
}
