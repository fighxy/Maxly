package app.orbitle.presentation.chat

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.ReactionUser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class ReactionUsersTest {
    @get:Rule val main = MainDispatcherRule()

    private val reacted = Message("5", "10", "2", "т", 1_000L, content = MessageContent(reactions = listOf(MessageReaction("👍", 2, false), MessageReaction("🔥", 1, true))))

    private fun repo(failing: Boolean = false) = object : app.orbitle.data.MessageRepository by FakeMessages() {
        override suspend fun reactionUsers(chatId: String, messageId: String): List<ReactionUser> {
            if (failing) throw RuntimeException()
            return listOf(ReactionUser("2", "Анна", null, "👍"), ReactionUser("3", " ", null, "👍"), ReactionUser("1", "Я", null, "🔥"))
        }
    }

    @Test
    fun loadsAndFilters() {
        val model = ReactionUsersModel("10", reacted, repo(), CoroutineScope(UnconfinedTestDispatcher()))
        model.load()
        assertEquals("Реакции: 3", model.title)
        assertEquals(3, model.state.value.visible.size)
        model.select("🔥")
        assertEquals(listOf("1"), model.state.value.visible.map { it.userId })
        assertEquals("Пользователь 3", ReactionUsersModel.name(model.state.value.users[1]))
    }

    @Test
    fun failureIsShown() {
        val model = ReactionUsersModel("10", reacted, repo(failing = true), CoroutineScope(UnconfinedTestDispatcher()))
        model.load()
        assertEquals(ReactionUsersState.Phase.Failed, model.state.value.phase)
    }

    @Test
    fun onlyGroupsOfferTheList() {
        val messages = FakeMessages()
        messages.list.value = listOf(reacted)
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Группа", ChatType.GROUP, updatedAtMs = 0))
        val vm = ChatViewModel("10", messages, ChatFormatter(ZoneOffset.UTC), now = { 10_000L })
        assertTrue(vm.canShowReactionUsers(reacted))
        assertFalse(vm.canShowReactionUsers(reacted.copy(content = MessageContent.empty)))
        messages.headerInfo.value = ChatHeaderInfo(Chat("10", "Анна", ChatType.PRIVATE, updatedAtMs = 0))
        assertFalse(vm.canShowReactionUsers(reacted))
    }
}
