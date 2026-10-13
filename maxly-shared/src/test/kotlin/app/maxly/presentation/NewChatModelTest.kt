package app.maxly.presentation

import app.maxly.MainDispatcherRule
import app.maxly.data.ChatRepository
import app.maxly.data.ContactRepository
import app.maxly.data.CoreFailure
import app.maxly.domain.Chat
import app.maxly.domain.Contact
import app.maxly.domain.ServerFolder
import app.maxly.presentation.chatlist.NewChatModel
import app.maxly.presentation.contacts.ContactsViewModel
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
    override val typing = MutableStateFlow<Map<String, List<app.maxly.domain.Typist>>>(emptyMap())
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
        // Сначала настройка канала, как в Max, потом канал открывается.
        assertEquals("91", model.state.value.channelSetup?.id)
        assertNull(model.state.value.opened)
        model.finishChannelSetup()
        assertEquals("91", model.state.value.opened?.id)
        assertNull(model.state.value.channelSetup)

        chats.channelId = null
        model.setTitle("Пусто")
        model.createChannel()
        assertEquals("Не удалось создать канал", model.state.value.error)
        assertNull(model.state.value.channelSetup)
    }

    private class Admin(base: app.maxly.data.ChatAdminRepository) : app.maxly.data.ChatAdminRepository by base {
        val added = mutableListOf<List<String>>()
        var link = "https://max.ru/join/abc"
        override suspend fun snapshot(chatId: String) = app.maxly.data.ChatAdminSnapshot(
            title = "Новости", description = "", link = link, ownerId = "1", commentsEnabled = null,
            onlyOwnerCanChangeIconTitle = false, allCanPinMessage = false, onlyAdminCanAddMember = false,
            onlyAdminCanCall = false, membersCanSeePrivateLink = false,
        )
        override suspend fun addMembers(chatId: String, userIds: List<String>) {
            added += userIds
        }
        override suspend fun revokeInviteLink(chatId: String): String {
            link = "https://max.ru/join/new"
            return link
        }
    }

    private class Sender(base: app.maxly.data.MessageRepository) : app.maxly.data.MessageRepository by base {
        val sent = mutableListOf<Pair<String, String>>()
        override suspend fun send(chatId: String, text: String, replyTo: String?) {
            sent += chatId to text
        }
    }

    private inline fun <reified T> unused(): T =
        java.lang.reflect.Proxy.newProxyInstance(T::class.java.classLoader, arrayOf(T::class.java)) { _, method, _ -> error("не нужно: ${method.name}") } as T

    @Test
    fun channelSetupLikeMax() {
        contacts.contacts.value = listOf(Contact("1", "Я"), Contact("6", "Маша"), Contact("7", "Бот", isBot = true), Contact("8", "Андрей"))
        val admin = Admin(unused())
        val sender = Sender(unused())
        val setup = app.maxly.presentation.chatlist.ChannelSetupModel("91", admin, sender, contacts) { "1" }
        val state = { setup.state.value }
        assertEquals("max.ru/join/abc", state().shortLink)
        assertEquals(listOf("Андрей", "Маша"), state().people.map { it.displayName })

        setup.askPublic()
        assertEquals(app.maxly.presentation.chatlist.ChannelPublicNotice.PUBLIC, state().publicNotice)
        setup.dismissPublic()

        setup.sendLink("5")
        assertEquals(listOf("5" to "https://max.ru/join/abc"), sender.sent)
        assertEquals("Ссылка отправлена", state().notice)
        setup.revokeLink()
        assertEquals("max.ru/join/new", state().shortLink)

        setup.next()
        assertEquals(app.maxly.presentation.chatlist.ChannelSetupStep.SUBSCRIBERS, state().step)
        setup.setQuery("маш")
        assertEquals(listOf("Маша"), state().shown.map { it.displayName })
        setup.addSubscribers()
        assertTrue(admin.added.isEmpty())
        setup.toggle("6")
        setup.toggle("8")
        setup.toggle("8")
        setup.addSubscribers()
        assertEquals(listOf(listOf("6")), admin.added)
        assertTrue(state().done)
    }

    @Test
    fun contactsTabPreparesTheSameDialog() {
        val model = ContactsViewModel(contacts, { "1" }, chats = chats)
        assertEquals((1L xor 6L).toString(), model.prepare("6", "Маша"))
        assertEquals(Triple((1L xor 6L).toString(), "6", "Маша"), chats.dialogs.single())
    }
}
