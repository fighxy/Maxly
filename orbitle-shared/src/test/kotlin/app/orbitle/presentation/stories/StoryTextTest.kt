package app.orbitle.presentation.stories

import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing
import app.orbitle.presentation.chatlist.ChatAvatar
import org.junit.Assert.assertEquals
import org.junit.Test

class StoryTextTest {
    private fun ring(name: String, url: String? = null, total: Int = 3, read: Int = 1) =
        StoryRing(StoryOwner("15"), name, url, 0, total, read)

    @Test
    fun avatarsAndTitles() {
        assertEquals(ChatAvatar(ChatAvatar.Kind.Initials("АП"), 1), StoryText.avatar(ring("Анна Петрова")))
        assertEquals(ChatAvatar.Kind.Photo("https://a", "АП"), StoryText.avatar(ring("Анна Петрова", "https://a")).kind)
        assertEquals("Без имени", StoryText.title(ring(""), own = false))
        assertEquals("Ваша история", StoryText.title(ring("Анна"), own = true))
    }

    @Test
    fun segmentsAreCapped() {
        assertEquals(3 to 1, StoryText.segments(ring("a")))
        assertEquals(30 to 30, StoryText.segments(ring("a", total = 50, read = 45)))
        assertEquals(1 to 0, StoryText.segments(ring("a", total = 0, read = 0)))
    }

    @Test
    fun agoLabels() {
        val now = 100_000_000L
        assertEquals("только что", StoryText.ago(now - 30_000, now))
        assertEquals("5 мин назад", StoryText.ago(now - 5 * 60_000, now))
        assertEquals("3 ч назад", StoryText.ago(now - 3 * 3_600_000, now))
        assertEquals("вчера", StoryText.ago(now - 25 * 3_600_000, now))
        assertEquals("", StoryText.ago(0, now))
        assertEquals("Публикация… 42%", StoryText.publishing(0.42f))
    }
}
