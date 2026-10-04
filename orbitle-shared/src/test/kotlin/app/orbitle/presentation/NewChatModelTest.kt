package app.orbitle.presentation

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatRepository
import app.orbitle.data.ContactRepository
import app.orbitle.data.CoreFailure
import app.orbitle.domain.Chat
import app.orbitle.domain.Contact
import app.orbitle.domain.ServerFolder
import app.orbitle.presentation.chatlist.NewChatModel
import app.orbitle.presentation.contacts.ContactsViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private class PhoneContacts : ContactRepository {
    override val contacts = MutableStateFlow<List<Contact>>(emptyList())
    val phones = mutableListOf<String>()
    var found: Contact? = null
    var lookupFailure: Throwable? = null
    val added = mutableListOf<String>()
    var addResult: Contact? = Contact("6", "Маша")

    override suspend fun sync() = Unit

    override suspend fun findByPhone(phone: String): Contact? {
        phones += phone
        lookupFailure?.let { throw it }
        return found
    }

    override suspend fun add(userId: String): Contact? {
        added += userId
        return addResult
    }
}

private class RecordingChats : ChatRepository {
    override val chats = MutableStateFlow<List<Chat>?>(emptyList())
    override val folders = MutableStateFlow<List<ServerFolder>>(emptyList())
    override val typing = MutableStateFlow<Map<String, List<String>>>(emptyMap())
    override suspend fun refresh() = Unit
    override suspend fun setPinned(chatId: String, pinned: Boolean) = Unit
    override fun clear() = Unit

    val groups = mutableListOf<Pair<String, List<String>>>()
    var groupId: String? = "90"
    var groupFailure: Throwable? = null
    val channels = mutableListOf<String>()
    var channelId: String? = "91"
    var channelFailure: Throwable? = null
    val dialogs = mutableListOf<Triple<String, String, String>>()

    override suspend fun createGroup(title: String, memberIds: List<String>): String? {
        groups += title to memberIds
        groupFailure?.let { throw it }
        return groupId
    }

    override suspend fun createChannel(title: String): String? {
        channels += title
        channelFailure?.let { throw it }
        return channelId
    }

    override suspend fun prepareDialog(chatId: String, peerId: String, title: String) {
        dialogs += Triple(chatId, peerId, title)
    }
}

class NewChatModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val contacts = PhoneContacts()
    private val chats = RecordingChats()
    private fun model(me: String? = "1") = NewChatModel(contacts, chats) { me }

    @Test
    fun dialogIdIsXorAndPhoneKeepsDigits() {
        assertEquals((1L xor 6L).toString(), NewChatModel.dialogId("1", "6"))
        assertNull(NewChatModel.dialogId(null, "6"))
        assertNull(NewChatModel.dialogId("1", "x"))
        assertEquals("+79001234567", NewChatModel.phonePayload("+7 (900) 123-45-67"))
        assertNull(NewChatModel.phonePayload("12345"))
        assertTrue(NewChatModel.isMissingPerson(CoreFailure("NOT_FOUND", "user.not.found")))
        assertTrue(NewChatModel.isMissingPerson(CoreFailure("MALFORMED_REPLY", null)))
        assertTrue(NewChatModel.isMissingPerson(CoreFailure("SERVER", "user.not.found")))
    }

    @Test
    fun contactWriteOpensXorDialog() {
        val model = model()
        model.writeTo("6", "Маша")
        val opened = model.state.value.opened
        assertEquals((1L xor 6L).toString(), opened?.id)
        assertEquals("Маша", opened?.title)
        assertEquals(Triple((1L xor 6L).toString(), "6", "Маша"), chats.dialogs.single())
    }

    @Test
    fun foundPhoneOpensThatDialogAndDoesNotAdd() {
        contacts.found = Contact("6", "Маша", phone = "79001234567")
        val model = model()
        model.setPhone("+7 (900) 123-45-67")
        model.lookup()
        assertEquals(listOf("+79001234567"), contacts.phones)
        assertEquals("6", model.state.value.found?.id)
        assertNull(model.state.value.opened)
        model.writeFound()
        assertEquals((1L xor 6L).toString(), model.state.value.opened?.id)
        assertTrue(contacts.added.isEmpty())
    }

    @Test
    fun missingPersonDoesNotOpenChat() {
        val model = model()
        model.setPhone("123")
        model.lookup()
        assertTrue(contacts.phones.isEmpty())
        assertEquals("Номер слишком короткий", model.state.value.error)
        assertNull(model.state.value.opened)

        model.setPhone("79001234567")
        model.lookup()
        assertEquals("Человек с таким номером не найден", model.state.value.error)
        assertNull(model.state.value.opened)

        contacts.lookupFailure = CoreFailure("SERVER", "proto.error")
        model.lookup()
        assertEquals("Не удалось найти человека", model.state.value.error)
        assertNull(model.state.value.opened)

        contacts.lookupFailure = CoreFailure("NOT_FOUND", "user.not.found")
        model.lookup()
        assertEquals("Человек с таким номером не найден", model.state.value.error)
        assertNull(model.state.value.opened)
    }

    @Test
    fun groupCreateSendsTitleAndSelectedIds() {
        val model = model()
        model.toggleMember("6")
        model.toggleMember("1")
        model.toggleMember("8")
        model.createGroup()
        assertEquals("Введите название", model.state.value.error)
        assertTrue(chats.groups.isEmpty())

        model.setTitle("  Друзья  ")
        model.createGroup()
        assertEquals("Друзья" to listOf("6", "8"), chats.groups.single())
        assertEquals("90", model.state.value.opened?.id)
        assertEquals("Друзья", model.state.value.opened?.title)
    }

    @Test
    fun channelCreateReturnsChatId() {
        val model = model()
        model.setTitle("Новости")
        model.createChannel()
        assertEquals(listOf("Новости"), chats.channels)
        assertEquals("91", model.state.value.opened?.id)

        chats.channelId = null
        model.setTitle("Пусто")
        model.createChannel()
        assertEquals("Не удалось создать канал", model.state.value.error)
        assertEquals("91", model.state.value.opened?.id)
    }

    @Test
    fun contactsTabPreparesTheSameDialog() {
        val model = ContactsViewModel(contacts, { "1" }, chats = chats)
        assertEquals((1L xor 6L).toString(), model.prepare("6", "Маша"))
        assertEquals(Triple((1L xor 6L).toString(), "6", "Маша"), chats.dialogs.single())
    }
}
