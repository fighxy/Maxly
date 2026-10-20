package app.maxly.presentation.contacts

import app.maxly.MainDispatcherRule
import app.maxly.data.ChatMapping
import app.maxly.data.CoreContactRepository
import app.maxly.data.MessageMapping
import app.maxly.domain.ChatProfile
import app.maxly.domain.Contact
import app.maxly.domain.MaxlyError
import com.maxly.core.api.ContactNames
import com.maxly.core.api.MaxMessage
import com.maxly.core.api.MaxUser
import com.maxly.core.state.MaxState
import com.maxly.core.state.MaxStore
import kotlinx.coroutines.flow.update
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import com.maxly.core.api.Chat as CoreChat

/** «Изменить контакт», удаление с отменой и «Добавить в контакты». */
class ContactProfileUxTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = EditableContacts()
    private val model by lazy { ContactsViewModel(repo, { "1" }) }
    private val actions get() = model.actions

    private fun removeAnna() {
        model.askRemove("2")
        actions.remove()
    }

    @Test
    fun editIsPrefilledWithTheCustomNameNotTheOwnName() {
        repo.list.value = listOf(Contact("2", "Анна", "Смирнова", label = "Анна Смирнова"))
        model.askRename("2")
        assertEquals(ContactDialog.Rename("2", "", ""), actions.state.value.dialog)
        repo.list.value = listOf(Contact("2", "Аня", "", customFirstName = "Аня"))
        model.askRename("2")
        assertEquals(ContactDialog.Rename("2", "Аня", ""), actions.state.value.dialog)
    }

    @Test
    fun customNameComesFromTheCustomEntryOnly() {
        val own = MaxUser.from(mapOf("id" to 2L, "names" to listOf(mapOf("firstName" to "Анна", "lastName" to "Смирнова", "type" to "ONEME"))))!!
        val state = MaxState(me = 1L, users = mapOf(2L to own))
        val plain = CoreContactRepository.contact(own, state)
        assertEquals("" to "", plain.customFirstName to plain.customLastName)
        val renamed = ContactNames.withCustom(own, "Аня", "С.")
        val custom = CoreContactRepository.contact(renamed, state.copy(users = mapOf(2L to renamed)))
        assertEquals("Аня" to "С.", custom.customFirstName to custom.customLastName)
    }

    @Test
    fun twoEmptyFieldsResetToTheOwnName() {
        model.askRename("2")
        actions.rename("  ", " ")
        assertEquals(Triple("2", "", null as String?), repo.renames.single())
        assertNull(actions.state.value.dialog)
        val back = repo.list.value.single()
        assertFalse(back.hasCustomName)
        assertEquals("Анна Смирнова", back.displayName)
    }

    @Test
    fun deleteShowsUndoAndUndoRestoresTheCustomName() {
        repo.list.value = listOf(Contact("2", "Аня", "", label = "Мама", customFirstName = "Аня"))
        model.askRemove("2")
        assertEquals(ContactDialog.Remove("2", "Мама"), actions.state.value.dialog)
        actions.remove()
        val undo = actions.state.value.undo!!
        assertEquals("Аня" to "", undo.customFirstName to undo.customLastName)
        actions.undo(undo.token)
        assertEquals(listOf("2"), repo.readded)
        // Своё имя, а не показанное («Мама» из книги).
        assertEquals(Triple("2", "Аня", null as String?), repo.renames.single())
        assertNull(actions.state.value.undo)
        assertEquals("Аня", repo.list.value.single().customFirstName)
    }

    @Test
    fun undoWithoutACustomNameOnlyReadds() {
        repo.list.value = listOf(Contact("2", "Анна", "Смирнова"))
        removeAnna()
        actions.undo(actions.state.value.undo!!.token)
        assertEquals(listOf("2"), repo.readded)
        assertTrue(repo.renames.isEmpty())
        assertNull(actions.state.value.notice)
    }

    @Test
    fun failedUndoShowsAnError() {
        removeAnna()
        repo.addFailure = MaxlyError.Unknown
        actions.undo(actions.state.value.undo!!.token)
        assertEquals("Не удалось вернуть контакт", actions.state.value.notice)
        assertTrue(repo.readded.isEmpty())
        assertNull(actions.state.value.undo)
    }

    @Test
    fun aSecondDeleteFinalizesThePendingUndo() {
        repo.list.value = listOf(
            Contact("2", "Аня", customFirstName = "Аня"),
            Contact("4", "Пётр", customFirstName = "Петя"),
        )
        removeAnna()
        val first = actions.state.value.undo!!
        model.askRemove("4")
        actions.remove()
        val second = actions.state.value.undo!!
        assertEquals("4", second.userId)
        assertNotEquals(first.token, second.token)
        // Отмена первого больше ничего не делает, его снекбар закрывается.
        actions.undo(first.token)
        actions.finishUndo(first.token)
        assertTrue(repo.readded.isEmpty())
        assertEquals(second, actions.state.value.undo)
        actions.undo(second.token)
        assertEquals(listOf("4"), repo.readded)
        assertEquals(Triple("4", "Петя", null as String?), repo.renames.single())
    }

    @Test
    fun dismissedSnackbarFinalizesTheDelete() {
        removeAnna()
        actions.finishUndo(actions.state.value.undo!!.token)
        assertNull(actions.state.value.undo)
        assertTrue(repo.readded.isEmpty())
    }

    @Test
    fun addContactVisibilityRules() {
        assertEquals(ProfileContactAction.EDIT, ProfileContactAction.of(ChatProfile.Kind.USER, isContact = true))
        assertEquals(ProfileContactAction.ADD, ProfileContactAction.of(ChatProfile.Kind.USER, isContact = false))
        assertEquals(ProfileContactAction.NONE, ProfileContactAction.of(ChatProfile.Kind.USER, isContact = false, loaded = false))
        assertEquals(ProfileContactAction.NONE, ProfileContactAction.of(ChatProfile.Kind.USER, isContact = true, isSelf = true))
        assertEquals(ProfileContactAction.NONE, ProfileContactAction.of(ChatProfile.Kind.USER, isContact = true, isBot = true))
        for (kind in listOf(ChatProfile.Kind.BOT, ChatProfile.Kind.GROUP, ChatProfile.Kind.CHANNEL, ChatProfile.Kind.SAVED)) {
            assertEquals(kind.name, ProfileContactAction.NONE, ProfileContactAction.of(kind, isContact = false))
            assertEquals(kind.name, ProfileContactAction.NONE, ProfileContactAction.of(kind, isContact = true))
        }
    }

    @Test
    fun addFromTheProfileCallsAdd() {
        repo.list.value = emptyList()
        actions.add("2")
        assertEquals(listOf("2"), repo.readded)
        assertEquals("Анна Смирнова в контактах", actions.state.value.notice)
    }

    @Test
    fun chatListHeaderAndSendersFollowARename() {
        val anna = MaxUser.from(mapOf("id" to 2L, "names" to listOf(mapOf("firstName" to "Анна", "lastName" to "Смирнова", "type" to "ONEME"))))!!
        val dialog = CoreChat.from(
            mapOf("id" to 3L, "type" to "DIALOG", "status" to "ACTIVE", "participants" to mapOf(1L to 0L, 2L to 0L),
                "lastMessage" to mapOf("id" to 5L, "sender" to 2L, "text" to "Привет", "time" to 1_000L, "type" to "USER")),
        )!!
        val store = MaxStore(initial = MaxState(me = 1L, users = mapOf(2L to anna), chats = mapOf(3L to dialog)))
        val message = MaxMessage.from(mapOf("id" to 5L, "sender" to 2L, "text" to "Привет", "time" to 1_000L, "type" to "USER"), 3L)!!
        assertEquals("Анна Смирнова", ChatMapping.chat(dialog, store.state.value, null, 0).title)

        // То, что кладёт в стор renameContact ядра.
        store.putContacts(listOf(ContactNames.withCustom(anna, "Аня", null)))
        val renamed = store.state.value
        assertEquals("Аня", ChatMapping.chat(renamed.chats.getValue(3L), renamed, null, 0).title)
        assertEquals("Аня", ChatMapping.chat(renamed.chats.getValue(3L), renamed, null, 0).lastMessage?.authorName)
        assertEquals("Аня", MessageMapping.message(message, 3L, renamed).authorName)

        // Два пустых поля: снова имя человека.
        store.putContacts(listOf(ContactNames.withCustom(anna, "", "")))
        assertEquals("Анна Смирнова", ChatMapping.chat(dialog, store.state.value, null, 0).title)
        assertNotNull(store.state.value.users[2L])
    }
}
