package app.orbitle.presentation.common

import app.orbitle.MainDispatcherRule
import app.orbitle.SharedFixtures
import app.orbitle.SharedFixtures.Companion.long
import app.orbitle.SharedFixtures.Companion.str
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.CoreContactRepository
import app.orbitle.data.PeerPresence
import app.orbitle.data.PresenceTime
import app.orbitle.data.ProfileRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatProfile
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.SharedMediaTab
import app.orbitle.presentation.chat.ChatFormatter
import app.orbitle.presentation.chat.FakeMessages
import app.orbitle.presentation.contacts.ContactsViewModel
import app.orbitle.presentation.contacts.EditableContacts
import app.orbitle.presentation.profile.ProfileViewModel
import com.max.core.api.MaxUser
import com.max.core.api.PresenceInfo
import com.max.core.api.UserName
import com.max.core.state.MaxState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.serialization.json.JsonObject
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.time.ZoneId

/**
 * Общие с iOS сценарии строки статуса из `test-fixtures/presence` (правила — в README каталога).
 * Запись `{seen, status}` протокола (`status` `-1` — поля нет, `seen` в секундах) идёт в стор
 * ядра и по той же дороге, что у приложения: контакт — [CoreContactRepository.contact] и строка
 * [ContactsViewModel] (`text`, с заглавной), шапка личного чата — [ChatFormatter.subtitle]
 * (`header`, со строчной). Профиль у нас пишется со строчной, как шапка: его строка сверяется с
 * `header`, а не с `text` (в iOS профиль — с заглавной, как контакты).
 */
class PresenceFixtureTest {
    @get:Rule val main = MainDispatcherRule()

    private val fixtures = SharedFixtures("presence")

    @Test
    fun everyFixtureIsPlayed() {
        // Каталог пока только в ветке iOS: без него проигрыватель не запускается.
        assumeTrue("нет test-fixtures/presence", present())
        val files = fixtures.files()
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        fixtures.finish("PresenceFixtureTest", files.size)
    }

    private fun play(file: String, fixture: JsonObject) {
        val zone = ZoneId.of(fixture["timeZone"].str!!)
        val now = fixture["nowMs"].long!!
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["id"].str}") {
                val status = case["status"].long!!.toInt()
                val seenMs = case["seenMs"].long!!
                val info = if (status < 0 && seenMs <= 0) null else PresenceInfo((seenMs / 1000).takeIf { seenMs > 0 }, status.takeIf { it >= 0 })
                check("контакт", case["text"].str, contactLine(info, zone, now))
                check("шапка", case["header"].str, headerLine(info, zone, now))
                check("профиль", case["header"].str, profileLine(info, zone, now))
            }
        }
    }

    private fun contactLine(info: PresenceInfo?, zone: ZoneId, now: Long): String {
        val state = MaxState(presence = listOfNotNull(info?.let { USER_ID to it }).toMap())
        val repo = EditableContacts()
        repo.list.value = listOf(CoreContactRepository.contact(user(), state))
        val model = ContactsViewModel(repo, { "1" }, zone, now = { now })
        return model.state.value.sections.single().rows.single().status
    }

    private fun headerLine(info: PresenceInfo?, zone: ZoneId, now: Long): String {
        val chat = Chat(USER_ID.toString(), "Анна", ChatType.PRIVATE, updatedAtMs = 0, isOnline = PresenceTime.isOnline(info))
        val header = ChatHeaderInfo(chat, lastSeenMs = PresenceTime.ms(info?.seen), presence = PresenceTime.status(info))
        return ChatFormatter(zone).subtitle(header, now).first
    }

    private fun profileLine(info: PresenceInfo?, zone: ZoneId, now: Long): String {
        val profile = ChatProfile(
            ChatProfile.Kind.USER, USER_ID.toString(), "Анна",
            isOnline = PresenceTime.isOnline(info), lastSeenMs = PresenceTime.ms(info?.seen), presence = PresenceTime.status(info),
        )
        val profiles = object : ProfileRepository {
            override fun cached(chatId: String): ChatProfile? = null
            override suspend fun profile(chatId: String): ChatProfile = profile
            override suspend fun sharedPage(chatId: String, tab: SharedMediaTab, beforeMessageId: String): List<Message> = emptyList()
            override fun presence(peerId: String): Flow<PeerPresence?> = flowOf(null)
        }
        val model = ProfileViewModel(USER_ID.toString(), "Анна", profiles, FakeMessages(), now = { now }, presence = PresenceText(zone))
        return model.state.value.subtitle
    }

    private fun present(): Boolean {
        var at: File? = File("").absoluteFile
        while (at != null) {
            if (File(at, "test-fixtures/presence").isDirectory) return true
            at = at.parentFile
        }
        return false
    }

    private fun user(): MaxUser = MaxUser(
        id = USER_ID,
        names = listOf(UserName(name = null, firstName = "Анна", lastName = null, type = "ONEME")),
        phone = 7900L,
        accountStatus = 0,
        status = null,
        description = null,
        link = null,
        baseUrl = null,
        photoId = null,
        updateTime = null,
        options = emptyList(),
        raw = emptyMap<String, Any?>(),
    )

    private companion object {
        const val USER_ID = 7L
    }
}
