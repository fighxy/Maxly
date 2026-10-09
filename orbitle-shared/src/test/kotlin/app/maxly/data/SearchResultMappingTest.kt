package app.maxly.data

import app.maxly.domain.ChatType
import com.max.core.api.PublicSearchHit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SearchResultMappingTest {
    private fun hit(chat: Map<String, Any?>? = null, user: Map<String, Any?>? = null) =
        PublicSearchHit.from(buildMap { chat?.let { put("chat", it) }; user?.let { put("user", it) } })!!

    @Test
    fun channelTakesTitleLinkAndIcon() {
        val found = CoreChatRepository.searchResultOf(
            hit(mapOf("id" to 7L, "type" to "CHANNEL", "title" to " Новости ", "baseIconUrl" to "https://i/7", "link" to "@news")),
        )!!
        assertEquals("7", found.id)
        assertEquals("Новости", found.title)
        assertEquals("@news", found.subtitle)
        assertEquals(ChatType.CHANNEL, found.type)
        // Ссылка-адрес: имя для упоминаний — путь ссылки (Chat.mentionName ядра).
        val linked = CoreChatRepository.searchResultOf(hit(mapOf("id" to 7L, "type" to "CHANNEL", "link" to "https://max.ru/news")))!!
        assertEquals("@news", linked.subtitle)
        assertEquals("https://i/7", found.avatarUrl)
    }

    @Test
    fun untitledGroupIsNamedByTypeAndShowsLastMessage() {
        val found = CoreChatRepository.searchResultOf(
            hit(mapOf("id" to 8L, "type" to "CHAT", "lastMessage" to mapOf("id" to 1L, "text" to " привет ", "time" to 1L, "sender" to 2L, "type" to "USER"))),
        )!!
        assertEquals("Группа", found.title)
        assertEquals("привет", found.subtitle)
        assertNull(found.avatarUrl)
    }

    @Test
    fun peopleAreSkipped() {
        assertNull(CoreChatRepository.searchResultOf(hit(user = mapOf("id" to 9L, "names" to listOf(mapOf("name" to "Анна"))))))
    }
}
