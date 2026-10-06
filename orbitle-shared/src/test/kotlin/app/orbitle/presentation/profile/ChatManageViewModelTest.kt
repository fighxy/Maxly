package app.orbitle.presentation.profile

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatAdminRepository
import app.orbitle.data.ChatAdminSnapshot
import app.orbitle.data.ChatPerson
import app.orbitle.data.GroupOption
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test

class ChatManageViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun saveRemoveAndAdminStayOnTheOwner() {
        val repo = FakeAdmin()
        val model = ChatManageViewModel("7", isChannel = false, selfId = "1", repository = repo)
        model.load()
        assertEquals("Команда", model.state.value.title)
        assertEquals(ChatPerson.Role.OWNER, model.state.value.role("1"))
        model.editTitle("Новая")
        model.saveCard()
        assertEquals("Новая", repo.savedTitle)
        model.removeMember("1")
        assertEquals("Владельца удалить нельзя", model.state.value.message)
        assertFalse(repo.removed.contains("1"))
        model.dismissMessage()
        model.removeMember("2")
        assertEquals(listOf("2"), repo.removed)
        model.setAdmin("2", true)
        assertEquals("2" to true, repo.admins.single())
    }

    @Test
    fun inviteLinkBecomesAnAddress() {
        assertEquals("https://max.ru/join/abc", ChatManageViewModel.absolute("join/abc"))
        assertEquals("https://max.ru/name", ChatManageViewModel.absolute("https://max.ru/name"))
    }
}

private class FakeAdmin : ChatAdminRepository {
    var savedTitle = ""
    val removed = mutableListOf<String>()
    val admins = mutableListOf<Pair<String, Boolean>>()
    override suspend fun snapshot(chatId: String) = ChatAdminSnapshot(
        "Команда", "чат", "https://max.ru/join/abc", "1", null, false, false, true, false, true,
    )
    override suspend fun saveCard(chatId: String, title: String, description: String) { savedTitle = title }
    override suspend fun setPhoto(chatId: String, jpeg: ByteArray) = Unit
    override suspend fun members(chatId: String) = listOf(
        ChatPerson("1", "Иван", ChatPerson.Role.OWNER),
        ChatPerson("2", "Анна"),
    )
    override suspend fun addMembers(chatId: String, userIds: List<String>) = Unit
    override suspend fun removeMember(chatId: String, userId: String) { removed += userId }
    override suspend fun setAdmin(chatId: String, userId: String, admin: Boolean) { admins += userId to admin }
    override suspend fun revokeInviteLink(chatId: String) = "https://max.ru/join/new"
    override suspend fun joinRequests(chatId: String) = emptyList<ChatPerson>()
    override suspend fun decideJoinRequest(chatId: String, userId: String, accept: Boolean) = Unit
    override suspend fun setOption(chatId: String, option: GroupOption, enabled: Boolean) = Unit
    override suspend fun setComments(chatId: String, enabled: Boolean) = Unit
    override suspend fun blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String) = Unit
}
