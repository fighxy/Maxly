package app.orbitle.presentation.contacts

import app.orbitle.MainDispatcherRule
import app.orbitle.data.AddressBook
import app.orbitle.data.ContactRepository
import app.orbitle.data.PreferenceStore
import app.orbitle.domain.Contact
import app.orbitle.domain.PhoneBookEntry
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PhoneBookMatcherTest {
    private fun contact(id: String, phone: String) = Contact(id = id, firstName = "К$id", phone = phone)

    @Test
    fun matchesByNormalizedPhone() {
        val entries = listOf(
            PhoneBookEntry("a", "Анна", listOf("+79991234567")),
            PhoneBookEntry("b", "Борис", listOf("+442079460958", "+79997654321")),
            PhoneBookEntry("c", "Вера", listOf("+79990000000")),
        )
        val contacts = listOf(
            contact("1", "79991234567"),
            contact("2", "+79997654321"),
            contact("3", "442079460958"),
            contact("4", ""),
        )
        val matches = PhoneBookMatcher.match(entries, contacts)
        assertEquals(
            listOf(
                PhoneBookMatch(entries[0], contacts[0], "+79991234567"),
                PhoneBookMatch(entries[1], contacts[2], "+442079460958"),
                PhoneBookMatch(entries[1], contacts[1], "+79997654321"),
            ),
            matches,
        )
    }

    @Test
    fun aContactIsMatchedOnceAndRussianTrunkPrefixDoesNotMatter() {
        val entries = listOf(
            PhoneBookEntry("a", "Анна", listOf("+79991234567")),
            PhoneBookEntry("a2", "Анна (рабочий)", listOf("+79991234567")),
        )
        val contacts = listOf(contact("1", "89991234567"))
        assertEquals(listOf(PhoneBookMatch(entries[0], contacts[0], "+79991234567")), PhoneBookMatcher.match(entries, contacts))
    }

    @Test
    fun nothingToMatch() {
        assertTrue(PhoneBookMatcher.match(emptyList(), listOf(contact("1", "79991234567"))).isEmpty())
        assertTrue(PhoneBookMatcher.match(listOf(PhoneBookEntry("a", "Анна", listOf("+79991234567"))), listOf(contact("1", ""))).isEmpty())
    }
}

class PhoneBookPermissionTest {
    @Test
    fun resolveFromSystemFacts() {
        assertEquals(PhoneBookPermission.GRANTED, PhoneBookPermission.resolve(granted = true, canAskAgain = false, askedBefore = false))
        assertEquals(PhoneBookPermission.GRANTED, PhoneBookPermission.resolve(granted = true, canAskAgain = true, askedBefore = true))
        assertEquals(PhoneBookPermission.NOT_ASKED, PhoneBookPermission.resolve(granted = false, canAskAgain = false, askedBefore = false))
        assertEquals(PhoneBookPermission.DENIED, PhoneBookPermission.resolve(granted = false, canAskAgain = true, askedBefore = true))
        // Пояснение система советует, даже если наш флаг потерялся.
        assertEquals(PhoneBookPermission.DENIED, PhoneBookPermission.resolve(granted = false, canAskAgain = true, askedBefore = false))
        assertEquals(PhoneBookPermission.BLOCKED, PhoneBookPermission.resolve(granted = false, canAskAgain = false, askedBefore = true))
    }
}

class PhoneBookViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private class FakeBook(override val isAvailable: Boolean = true) : AddressBook {
        var book = listOf(
            PhoneBookEntry("a", "Анна", listOf("+79991234567")),
            PhoneBookEntry("b", "Борис", listOf("+79997654321")),
        )
        var reads = 0
        var failure: Exception? = null
        var gate: CompletableDeferred<Unit>? = null
        override suspend fun entries(): List<PhoneBookEntry> {
            reads++
            gate?.await()
            failure?.let { throw it }
            return book
        }
    }

    private class FakeContacts : ContactRepository {
        override val contacts = MutableStateFlow<List<Contact>>(emptyList())
        override suspend fun sync() = Unit
    }

    private class MapStore(val values: MutableMap<String, String> = mutableMapOf()) : PreferenceStore {
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) { values[key] = value }
    }

    private val book = FakeBook()
    private val contacts = FakeContacts()
    private val prefs = MapStore()

    private fun model(addressBook: AddressBook = book, store: PreferenceStore? = prefs) =
        PhoneBookViewModel(addressBook, contacts, currentUserId = { "100" }, prefs = store)

    @Test
    fun theWholeBookGoesToTheCoreAndRevokeSendsAnEmptyOne() {
        val published = mutableListOf<List<PhoneBookEntry>>()
        val model = PhoneBookViewModel(book, contacts, currentUserId = { "100" }, prefs = prefs, sink = { published += it })
        model.findFriends()
        model.systemPromptShown()
        model.permissionResult(granted = true, canAskAgain = false)
        assertEquals(listOf(book.book), published)
        book.book = book.book.take(1)
        model.refresh()
        assertEquals(book.book, published.last())
        model.permissionChecked(granted = false, canAskAgain = false)
        assertEquals(emptyList<PhoneBookEntry>(), published.last())
        assertEquals(3, published.size)
    }

    @Test
    fun firstTapShowsTheRationaleAndNothingIsReadOnItsOwn() {
        val model = model()
        model.permissionChecked(granted = false, canAskAgain = false)
        assertEquals(PhoneBookPermission.NOT_ASKED, model.state.value.permission)
        assertNull(model.state.value.prompt)
        assertEquals(0, book.reads)
        model.findFriends()
        assertEquals(PhoneBookPrompt.RATIONALE, model.state.value.prompt)
        model.dismissPrompt()
        assertNull(model.state.value.prompt)
        assertEquals(0, book.reads)
    }

    @Test
    fun grantedReadsTheBookAndMatchesContacts() {
        val model = model()
        model.findFriends()
        model.systemPromptShown()
        assertNull(model.state.value.prompt)
        contacts.contacts.value = listOf(
            Contact(id = "1", firstName = "Анна", phone = "79991234567"),
            Contact(id = "100", firstName = "Я", phone = "79997654321"),
        )
        model.permissionResult(granted = true, canAskAgain = false)
        val state = model.state.value
        assertEquals(PhoneBookPermission.GRANTED, state.permission)
        assertEquals(2, state.entryCount)
        // Свой номер не в счёт.
        assertEquals(1, state.matchCount)
        assertEquals("2 контакта в телефонной книге · уже в ваших контактах: 1", state.summary)
        assertEquals(listOf("1"), model.matches.map { it.contact.id })
        assertEquals(2, model.entries.size)
        // Контакты изменились — совпадения пересчитаны без нового чтения книги.
        contacts.contacts.value = contacts.contacts.value + Contact(id = "2", firstName = "Борис", phone = "+7 999 765-43-21")
        assertEquals(2, model.state.value.matchCount)
        assertEquals(1, book.reads)
        // Повторное нажатие с разрешением — сразу чтение, без пояснения.
        model.findFriends()
        assertNull(model.state.value.prompt)
        assertEquals(2, book.reads)
    }

    @Test
    fun deniedCanBeAskedAgain() {
        val model = model()
        model.findFriends()
        model.systemPromptShown()
        model.permissionResult(granted = false, canAskAgain = true)
        assertEquals(PhoneBookPermission.DENIED, model.state.value.permission)
        assertEquals(PhoneBookPrompt.DENIED, model.state.value.prompt)
        model.dismissPrompt()
        model.findFriends()
        assertEquals(PhoneBookPrompt.RATIONALE, model.state.value.prompt)
        assertEquals(0, book.reads)
    }

    @Test
    fun blockedLeadsToSettingsAndReadsAfterComingBack() {
        val model = model()
        model.findFriends()
        model.systemPromptShown()
        model.permissionResult(granted = false, canAskAgain = false)
        assertEquals(PhoneBookPermission.BLOCKED, model.state.value.permission)
        assertEquals(PhoneBookPrompt.BLOCKED, model.state.value.prompt)
        assertEquals("Доступ к контактам запрещён в настройках", model.state.value.summary)
        model.dismissPrompt()
        model.findFriends()
        assertEquals(PhoneBookPrompt.BLOCKED, model.state.value.prompt)
        model.openedSettings()
        assertNull(model.state.value.prompt)
        // Вернулись без разрешения — ничего не читается.
        model.permissionChecked(granted = false, canAskAgain = false)
        assertEquals(0, book.reads)
        // Разрешили в настройках.
        model.permissionChecked(granted = true, canAskAgain = false)
        assertEquals(PhoneBookPermission.GRANTED, model.state.value.permission)
        assertEquals(1, book.reads)
        // Обычный возврат в приложение книгу заново не читает.
        model.permissionChecked(granted = true, canAskAgain = false)
        assertEquals(1, book.reads)
    }

    @Test
    fun askedFlagSurvivesRestartSoBlockedIsRecognized() {
        model().apply {
            findFriends()
            systemPromptShown()
            permissionResult(granted = false, canAskAgain = false)
        }
        val again = model()
        again.permissionChecked(granted = false, canAskAgain = false)
        assertEquals(PhoneBookPermission.BLOCKED, again.state.value.permission)
        // Без хранилища после перезапуска это снова «не спрашивали».
        val fresh = model(store = null)
        fresh.permissionChecked(granted = false, canAskAgain = false)
        assertEquals(PhoneBookPermission.NOT_ASKED, fresh.state.value.permission)
    }

    @Test
    fun revokedPermissionForgetsTheBook() {
        val model = model()
        model.permissionChecked(granted = true, canAskAgain = false)
        model.refresh()
        assertEquals(2, model.state.value.entryCount)
        model.permissionChecked(granted = false, canAskAgain = true)
        assertNull(model.state.value.entryCount)
        assertTrue(model.entries.isEmpty())
        assertTrue(model.matches.isEmpty())
        assertEquals("Знакомые из телефонной книги", model.state.value.summary)
        // Без разрешения обновить нечего.
        model.refresh()
        assertEquals(1, book.reads)
    }

    @Test
    fun loadingAndFailure() {
        val model = model()
        model.permissionChecked(granted = true, canAskAgain = false)
        book.gate = CompletableDeferred()
        model.refresh()
        assertTrue(model.state.value.isLoading)
        assertEquals("Читаем телефонную книгу…", model.state.value.summary)
        // Второе нажатие во время чтения не начинает новое.
        model.refresh()
        assertEquals(1, book.reads)
        book.failure = SecurityException("нет доступа")
        book.gate!!.complete(Unit)
        assertFalse(model.state.value.isLoading)
        assertEquals("Не удалось прочитать контакты телефона", model.state.value.summary)
        assertNull(model.state.value.entryCount)
        book.failure = null
        model.refresh()
        assertNull(model.state.value.error)
        assertEquals("2 контакта в телефонной книге", model.state.value.summary)
    }

    @Test
    fun withoutAnAddressBookThereIsNothingToDo() {
        val model = model(FakeBook(isAvailable = false))
        assertFalse(model.state.value.isAvailable)
        model.findFriends()
        assertNull(model.state.value.prompt)
    }

    @Test
    fun summaryPlurals() {
        fun summary(count: Int) = PhoneBookUiState(entryCount = count).summary
        assertEquals("1 контакт в телефонной книге", summary(1))
        assertEquals("5 контактов в телефонной книге", summary(5))
        assertEquals("21 контакт в телефонной книге", summary(21))
        assertEquals("0 контактов в телефонной книге", summary(0))
    }
}
