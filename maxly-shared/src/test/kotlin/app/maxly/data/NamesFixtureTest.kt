package app.maxly.data

import app.maxly.SharedFixtures
import app.maxly.SharedFixtures.Companion.array
import app.maxly.SharedFixtures.Companion.bool
import app.maxly.SharedFixtures.Companion.obj
import app.maxly.SharedFixtures.Companion.raw
import app.maxly.SharedFixtures.Companion.str
import app.maxly.domain.PhoneBook
import app.maxly.domain.PhoneBookRow
import com.maxly.core.api.MaxMessage
import com.maxly.core.api.MaxUser
import com.maxly.core.api.PhoneNumbers
import com.maxly.core.state.MaxState
import com.maxly.core.state.StateReducer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertTrue
import org.junit.Test
import com.maxly.core.api.Chat as CoreChat

/**
 * Общие с iOS сценарии имён из `test-fixtures/names` (правила — в README каталога).
 * `phone` — [PhoneNumbers.normalize] ядра как есть. `address-book` — путь книги устройства:
 * строки системы → [PhoneBook.entries] → [CoreAddressBookSink.contacts] →
 * [StateReducer.setAddressBook]. `display-name` — та же книга (выключенная — пустая, как
 * `PhoneBookViewModel` её и отдаёт), пользователь — [MaxUser.from]; имя сверяется везде, где его
 * показывает клиент: автор сообщения, название личного чата и контакт (как в [DisplayNamesTest]).
 */
class NamesFixtureTest {
    private val fixtures = SharedFixtures("names")

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures.files()
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        assertTrue("сыграно ${fixtures.played} случаев", fixtures.played >= files.size)
        fixtures.finish("NamesFixtureTest", files.size)
    }

    private fun play(file: String, fixture: JsonObject) {
        val kind = fixture["kind"].str
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["name"].str}") {
                when (kind) {
                    "phone" -> phone(case)
                    "address-book" -> addressBook(case)
                    "display-name" -> displayName(case)
                    else -> error("$file: незнакомый kind $kind")
                }
            }
        }
    }

    // ---- kind: phone -----------------------------------------------------------------------------

    private fun SharedFixtures.Case.phone(case: JsonObject) {
        check("номер", case["expect"].str, PhoneNumbers.normalize(case["raw"]?.raw()))
    }

    // ---- kind: address-book ----------------------------------------------------------------------

    private fun SharedFixtures.Case.addressBook(case: JsonObject) {
        val expected = case["expect"].obj!!.mapValues { it.value.str }
        check("книга", expected, book(case["entries"]))
    }

    // ---- kind: display-name ----------------------------------------------------------------------

    private fun SharedFixtures.Case.displayName(case: JsonObject) {
        val enabled = case["addressBookEnabled"].bool ?: error("нет addressBookEnabled")
        val raw = LinkedHashMap<String, Any?>((case["user"]!!.raw() as Map<*, *>).mapKeys { it.key.toString() })
        raw["id"] = PEER
        val user = MaxUser.from(raw)!!
        val dialog = CoreChat.from(mapOf("id" to DIALOG, "type" to "DIALOG", "status" to "ACTIVE", "participants" to mapOf(ME to 0L, PEER to 0L)))!!
        val state = MaxState(me = ME, users = mapOf(PEER to user), chats = mapOf(DIALOG to dialog), addressBook = if (enabled) book(case["addressBook"]) else emptyMap())
        val expected = case["expect"].str
        val message = MaxMessage.from(mapOf("id" to 5L, "sender" to PEER, "text" to "Привет", "time" to 1_000L, "type" to "USER"), DIALOG)!!
        check("автор сообщения", expected, MessageMapping.message(message, DIALOG, state).authorName)
        check("личный чат", expected, ChatMapping.chat(dialog, state, null, 0).title)
        check("контакт", expected, CoreContactRepository.contact(user, state).displayName)
    }

    // ---- помощники ------------------------------------------------------------------------------

    /** Книга сценария (`[{name, phones}]`) — строками системы, по одной на номер — в книгу ядра. */
    private fun book(entries: JsonElement?): Map<String, String> {
        val rows = entries.array.flatMapIndexed { index, entry ->
            entry as JsonObject
            entry["phones"].array.map { PhoneBookRow(entryId = "e$index", displayName = entry["name"].str, number = it.str) }
        }
        return StateReducer.setAddressBook(MaxState(me = ME), CoreAddressBookSink.contacts(PhoneBook.entries(rows))).addressBook
    }

    private companion object {
        const val ME = 1L
        const val PEER = 2L
        const val DIALOG = 3L
    }
}
