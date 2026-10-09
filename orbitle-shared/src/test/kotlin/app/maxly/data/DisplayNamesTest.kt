package app.maxly.data

import com.maxly.core.api.MaxMessage
import com.maxly.core.api.MaxUser
import com.maxly.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Test
import com.maxly.core.api.Chat as CoreChat

/** Имена людей везде — по правилу ядра: книга, своё имя контакта, имя профиля, телефон. */
class DisplayNamesTest {
    private val me = 1L
    private val anna = MaxUser.from(
        mapOf(
            "id" to 2L,
            "phone" to 79991234567L,
            "names" to listOf(mapOf("firstName" to "Анна", "lastName" to "Смирнова", "type" to "ONEME")),
        ),
    )!!
    private val dialog = CoreChat.from(
        mapOf("id" to 3L, "type" to "DIALOG", "status" to "ACTIVE", "participants" to mapOf(me to 0L, 2L to 0L),
            "lastMessage" to mapOf("id" to 5L, "sender" to 2L, "text" to "Привет", "time" to 1_000L, "type" to "USER")),
    )!!
    private val book = MaxState(
        me = me,
        users = mapOf(2L to anna),
        chats = mapOf(3L to dialog),
        addressBook = mapOf("+79991234567" to "Мама"),
    )

    @Test
    fun theBookNameWinsInTheChatListAuthorsAndContacts() {
        val chat = ChatMapping.chat(dialog, book, null, 0)
        assertEquals("Мама", chat.title)
        assertEquals("Мама", chat.lastMessage?.authorName)
        val message = MaxMessage.from(mapOf("id" to 5L, "sender" to 2L, "text" to "Привет", "time" to 1_000L, "type" to "USER"), 3L)!!
        assertEquals("Мама", MessageMapping.message(message, 3L, book).authorName)
        assertEquals("Мама", CoreContactRepository.contact(anna, book).displayName)
        // Своё имя контакта и фамилия для правки остаются как есть.
        assertEquals("Анна" to "Смирнова", CoreContactRepository.contact(anna, book).let { it.firstName to it.lastName })
    }

    @Test
    fun withoutTheBookTheProfileNameAndAFallbackForStrangers() {
        val plain = book.copy(addressBook = emptyMap())
        assertEquals("Анна Смирнова", ChatMapping.chat(dialog, plain, null, 0).title)
        val stranger = MaxMessage.from(mapOf("id" to 6L, "sender" to 9L, "text" to "?", "time" to 1_000L, "type" to "USER"), 3L)!!
        assertEquals("Участник", MessageMapping.message(stranger, 3L, plain).authorName)
    }
}
