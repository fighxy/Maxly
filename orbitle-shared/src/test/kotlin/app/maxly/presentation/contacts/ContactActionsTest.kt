package app.maxly.presentation.contacts

import app.maxly.MainDispatcherRule
import app.maxly.data.AddedContact
import app.maxly.data.ContactRepository
import app.maxly.domain.ChatProfile
import app.maxly.domain.Contact
import app.maxly.domain.OrbitleError
import app.maxly.domain.SharedMediaTab
import app.maxly.presentation.chat.FakeMessages
import app.maxly.presentation.profile.ProfileViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Контакты в памяти с правкой, удалением и добавлением по номеру. */
class EditableContacts : ContactRepository {
    val list = MutableStateFlow(listOf(Contact("2", "Анна", "Смирнова", phone = "79001112233")))
    val pushes = MutableSharedFlow<Contact>(extraBufferCapacity = 4)
    val renames = mutableListOf<Triple<String, String, String?>>()
    val removed = mutableListOf<String>()
    val added = mutableListOf<Triple<String, String?, String?>>()
    var failure: Exception? = null
    var known = false
    override val contacts = list
    override val changes = pushes
    override suspend fun sync() = Unit
    override suspend fun rename(userId: String, firstName: String, lastName: String?): Contact {
        failure?.let { throw it }
        renames += Triple(userId, firstName, lastName)
        val renamed = Contact(userId, firstName, lastName.orEmpty())
        list.update { all -> all.map { if (it.id == userId) renamed else it } }
        return renamed
    }
    override suspend fun remove(userId: String): Boolean {
        failure?.let { throw it }
        removed += userId
        list.update { all -> all.filterNot { it.id == userId } }
        return true
    }
    override suspend fun addByPhone(phone: String, firstName: String?, lastName: String?): AddedContact {
        failure?.let { throw it }
        added += Triple(phone, firstName, lastName)
        return AddedContact(Contact("9", firstName ?: "Пётр"), isNew = !known)
    }
}

class ContactActionsTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = EditableContacts()
    private val model by lazy { ContactsViewModel(repo, { "1" }) }

    @Test
    fun renameChecksTheNameAndClosesOnSuccess() {
        model.askRename("2")
        assertEquals(ContactDialog.Rename("2", "Анна", "Смирнова"), model.actions.state.value.dialog)
        model.actions.rename("А".repeat(65), "")
        assertEquals("Имя и фамилия — не длиннее 64 символов", model.actions.state.value.error)
        assertTrue(repo.renames.isEmpty())
        model.actions.rename(" Аня ", "  ")
        assertEquals(listOf(Triple("2", "Аня", null as String?)), repo.renames)
        assertNull(model.actions.state.value.dialog)
        assertEquals("Имя контакта изменено", model.actions.state.value.notice)
        assertEquals("Аня", model.state.value.sections.single().rows.single().title)
    }

    @Test
    fun renameSendsAnEmptyFirstNameAsTheCoreAllows() {
        model.askRename("2")
        model.actions.rename("  ", " Смирнова ")
        assertEquals(listOf(Triple("2", "", "Смирнова" as String?)), repo.renames)
        assertNull(model.actions.state.value.dialog)
        assertNull(model.actions.state.value.error)
    }

    @Test
    fun removeAsksFirstAndKeepsTheDialogOnFailure() {
        model.askRemove("2")
        assertEquals(ContactDialog.Remove("2", "Анна Смирнова"), model.actions.state.value.dialog)
        repo.failure = OrbitleError.Rejected("Сервер занят")
        model.actions.remove()
        assertEquals("Сервер занят", model.actions.state.value.error)
        assertTrue(model.actions.state.value.dialog is ContactDialog.Remove)
        repo.failure = null
        model.actions.remove()
        assertEquals(listOf("2"), repo.removed)
        assertEquals("Контакт удалён", model.actions.state.value.notice)
        assertEquals(ContactsUiState.Content.EMPTY, model.state.value.content)
    }

    @Test
    fun addByPhoneSendsTheNormalizedNumber() {
        model.actions.askAddByPhone()
        model.actions.addByPhone("доб. 12", "", "")
        assertEquals("Номер не похож на телефон", model.actions.state.value.error)
        model.actions.addByPhone("8 (900) 555-11-22", "Пётр", "")
        assertEquals(listOf(Triple("+79005551122", "Пётр", null as String?)), repo.added)
        assertEquals("Пётр в контактах", model.actions.state.value.notice)

        repo.known = true
        model.actions.askAddByPhone()
        model.actions.addByPhone("+7 900 555 11 22", "", "")
        assertEquals(Triple("+79005551122", null as String?, null as String?), repo.added.last())
        assertEquals("Пётр уже в контактах", model.actions.state.value.notice)
    }
}

private class OneProfile(var title: String) : app.maxly.data.ProfileRepository {
    override fun cached(chatId: String) = ChatProfile(ChatProfile.Kind.USER, chatId, title, peerId = "2")
    override suspend fun profile(chatId: String) = cached(chatId)
    override suspend fun sharedPage(chatId: String, tab: SharedMediaTab, beforeMessageId: String) = emptyList<app.maxly.domain.Message>()
}

class ProfileContactTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = EditableContacts()
    private val profiles = OneProfile("Анна Смирнова")
    private fun vm() = ProfileViewModel("3", null, profiles, FakeMessages(), contacts = repo)

    @Test
    fun contactPeerCanBeRenamedAndTheHeaderFollows() {
        val model = vm()
        assertEquals("2", model.state.value.contact?.id)
        model.askRenameContact()
        profiles.title = "Аня"
        model.contactActions!!.rename("Аня", "")
        assertEquals("Аня", model.state.value.title)
    }

    @Test
    fun renameOnAnotherDeviceUpdatesTheHeader() {
        val model = vm()
        profiles.title = "Анюта"
        repo.pushes.tryEmit(Contact("2", "Анюта"))
        assertEquals("Анюта", model.state.value.title)
    }

    @Test
    fun removedPeerLosesTheContactActions() {
        val model = vm()
        model.askRemoveContact()
        model.contactActions!!.remove()
        assertNull(model.state.value.contact)
    }
}
