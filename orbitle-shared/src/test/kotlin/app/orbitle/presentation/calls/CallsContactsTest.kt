package app.orbitle.presentation.calls

import app.orbitle.MainDispatcherRule
import app.orbitle.data.AppearanceSettings
import app.orbitle.data.CallRepository
import app.orbitle.data.ContactRepository
import app.orbitle.data.CoreCallRepository
import app.orbitle.data.PreferenceStore
import app.orbitle.domain.CallOutcome
import app.orbitle.domain.CallRecord
import app.orbitle.domain.ChatWallpaper
import app.orbitle.domain.Contact
import app.orbitle.domain.TextSizeStep
import app.orbitle.domain.ThemeMode
import app.orbitle.domain.WallpaperImage
import app.orbitle.presentation.contacts.ContactsUiState
import app.orbitle.presentation.contacts.ContactsViewModel
import com.max.core.calls.CallLogEntry
import com.max.core.api.MaxUser
import com.max.core.state.MaxState
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class FakeCalls : CallRepository {
    override val calls = MutableStateFlow<List<CallRecord>?>(null)
    var refreshes = 0
    override suspend fun refresh() { refreshes++ }
    override fun clear() { calls.value = null }
}

class CallsViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val repo = FakeCalls()
    private val now = 1_790_683_200_000L // 2026-09-29 12:00 UTC
    private val hour = 3_600_000L
    private val marks = InMemoryCallMarks()

    private fun vm() = CallsViewModel(repo, marks, ZoneOffset.UTC) { now }
    private fun call(id: String, peer: String = "2", outgoing: Boolean = false, outcome: CallOutcome = CallOutcome.ANSWERED, at: Long = now, video: Boolean = false) =
        CallRecord(id, peer, "Анна", outgoing = outgoing, outcome = outcome, timeMs = at, isVideo = video, chatId = "10")

    @Test
    fun groupsNeighboursOfOnePeerAndKind() {
        val model = vm()
        repo.calls.value = listOf(
            call("1", outcome = CallOutcome.MISSED, at = now - hour),
            call("2", outcome = CallOutcome.MISSED, at = now - 2 * hour),
            call("3", outgoing = true, at = now - 3 * hour),
            call("4", peer = "3", at = now - 30 * hour, video = true),
        )
        val rows = model.state.value.rows
        assertEquals(listOf("Анна (2)", "Анна", "Анна"), rows.map { it.title })
        assertTrue(rows[0].isMissed)
        assertEquals("Пропущенный", rows[0].status)
        assertEquals("Исходящий", rows[1].status)
        assertEquals("Входящий видеозвонок", rows[2].status)
        assertEquals("11:00", rows[0].dateText)
        assertEquals("28 сен", rows[2].dateText)
    }

    @Test
    fun missedFilterAndHide() {
        val model = vm()
        repo.calls.value = listOf(call("1", outcome = CallOutcome.MISSED), call("2", outgoing = true, at = now - 1))
        model.setFilter(CallsFilter.MISSED)
        assertEquals(listOf("1"), model.state.value.rows.map { it.id })
        model.hide(model.state.value.rows.first())
        assertEquals(CallsUiState.Content.EMPTY, model.state.value.content)
        assertEquals(setOf("1"), marks.hiddenIds)
    }

    @Test
    fun badgeCountsMissedAfterLastSeen() {
        marks.lastSeenMs = now - 2 * hour
        val model = vm()
        repo.calls.value = listOf(call("1", outcome = CallOutcome.MISSED, at = now - hour), call("2", outcome = CallOutcome.MISSED, at = now - 3 * hour))
        assertEquals(1, model.state.value.unseenMissed)
        model.appeared()
        assertEquals(0, model.state.value.unseenMissed)
        assertEquals(1, repo.refreshes)
        assertEquals(now - hour, marks.lastSeenMs)
    }

    @Test
    fun kindsMatchIosRules() {
        assertEquals(CallsViewModel.Kind.CANCELLED, CallsViewModel.kind(call("1", outgoing = true, outcome = CallOutcome.DECLINED)))
        assertEquals(CallsViewModel.Kind.DECLINED, CallsViewModel.kind(call("1", outcome = CallOutcome.DECLINED)))
        assertEquals(CallsViewModel.Kind.CANCELLED, CallsViewModel.kind(call("1", outcome = CallOutcome.CANCELLED)))
    }

    private fun entry(sender: Long, hangup: String?, duration: Long, contacts: List<Long> = listOf(1, 2)) =
        CallLogEntry(messageId = 9, chatId = 10, time = now, senderId = sender, contactIds = contacts, hangupType = hangup, duration = duration, callType = "AUDIO", raw = emptyMap<Any, Any>())

    @Test
    fun coreEntriesBecomeRecords() {
        val anna = MaxUser.from(mapOf("id" to 2L, "names" to listOf(mapOf("name" to "Анна"))))!!
        val state = MaxState(me = 1, users = mapOf(2L to anna))
        val out = CoreCallRepository.record(entry(1, "HUNGUP", 5_000), 1, state)
        assertTrue(out.outgoing)
        assertEquals(CallOutcome.ANSWERED, out.outcome)
        assertEquals("Анна", out.title)
        assertEquals("2", out.peerId)
        assertEquals(CallOutcome.DECLINED, CoreCallRepository.record(entry(1, "REJECTED", 0), 1, state).outcome)
        assertEquals(CallOutcome.CANCELLED, CoreCallRepository.record(entry(1, null, 0), 1, state).outcome)
        val missed = CoreCallRepository.record(entry(2, "MISSED", 0), 1, state)
        assertTrue(missed.isMissed)
        val group = CoreCallRepository.record(entry(0, "HUNGUP", 5_000, listOf(3, 4, 5)), 1, state)
        assertTrue(group.isGroup)
        assertEquals("Групповой звонок", group.title)
    }
}

class FakeContacts : ContactRepository {
    override val contacts = MutableStateFlow<List<Contact>>(emptyList())
    var syncs = 0
    override suspend fun sync() { syncs++ }
}

class ContactsViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val repo = FakeContacts()
    private fun vm() = ContactsViewModel(repo, { "1" }, ZoneOffset.UTC, now = { 1_790_683_200_000L })

    @Test
    fun sectionsCyrillicFirstWithoutSelf() {
        val model = vm()
        repo.contacts.value = listOf(
            Contact("1", "Я"), Contact("2", "Борис"), Contact("3", "alex"), Contact("4", "Ёлка"), Contact("5", "Анна", isOnline = true), Contact("6", "42"),
        )
        val state = model.state.value
        assertEquals(listOf("А", "Б", "Е", "A", "#"), state.sections.map { it.letter })
        assertEquals(5, state.count)
        assertEquals("В сети", state.sections.first().rows.first().status)
        assertEquals(ContactsUiState.Content.READY, state.content)
    }

    @Test
    fun searchByNameAndPhone() {
        val model = vm()
        repo.contacts.value = listOf(Contact("2", "Борис", phone = "79001234567"), Contact("3", "Йоган"), Contact("4", "Иван"))
        model.setQuery("бор")
        assertEquals(listOf("2"), model.state.value.searchResults.map { it.id })
        model.setQuery("1234")
        assertEquals(listOf("2"), model.state.value.searchResults.map { it.id })
        model.setQuery("й")
        assertEquals(listOf("3"), model.state.value.searchResults.map { it.id })
    }

    @Test
    fun dialogIdIsXorAndSyncOnce() {
        val model = vm()
        assertEquals((1L xor 6L).toString(), model.chatId("6"))
        assertNull(model.chatId("x"))
        model.appeared()
        model.appeared()
        assertEquals(1, repo.syncs)
        assertEquals(ContactsUiState.Content.EMPTY, model.state.value.content)
    }

    @Test
    fun indexTitles() {
        assertEquals("Е", ContactsViewModel.indexTitle("ёж"))
        assertEquals("E", ContactsViewModel.indexTitle("Émile"))
        assertEquals("#", ContactsViewModel.indexTitle(" "))
        assertFalse(ContactsViewModel.compare("Анна", "Борис") > 0)
        assertTrue(ContactsViewModel.compare("Zoe", "Анна") > 0)
    }
}

class AppearanceSettingsTest {
    private val map = mutableMapOf<String, String>()
    private val store = object : PreferenceStore {
        override fun get(key: String) = map[key]
        override fun put(key: String, value: String) { map[key] = value }
    }

    @Test
    fun defaultsAndPersistence() {
        val settings = AppearanceSettings(store)
        assertEquals(TextSizeStep.STANDARD, settings.state.value.textSize)
        settings.setTextSize(TextSizeStep.XX_LARGE)
        settings.setTheme(ThemeMode.DARK)
        settings.setWallpaper(ChatWallpaper.AUTUMN_NIGHT)
        val again = AppearanceSettings(store).state.value
        assertEquals(TextSizeStep.XX_LARGE, again.textSize)
        assertEquals(ThemeMode.DARK, again.theme)
        assertEquals(ChatWallpaper.AUTUMN_NIGHT, again.wallpaper)
        map["appearance.theme"] = "BROKEN"
        assertEquals(ThemeMode.SYSTEM, AppearanceSettings(store).state.value.theme)
    }

    @Test
    fun textSizeSteps() {
        assertEquals("17\u00A0пт · 100\u00A0%", TextSizeStep.STANDARD.caption)
        assertEquals(82, TextSizeStep.X_SMALL.percent)
        assertEquals(135, TextSizeStep.XXX_LARGE.percent)
        assertEquals(TextSizeStep.XXX_LARGE, TextSizeStep.of(99))
        assertEquals(TextSizeStep.X_SMALL, TextSizeStep.of(-3))
    }

    @Test
    fun autumnAutoFollowsTheme() {
        assertEquals(WallpaperImage.AUTUMN, ChatWallpaper.AUTUMN_AUTO.image(dark = false))
        assertEquals(WallpaperImage.AUTUMN_DARK, ChatWallpaper.AUTUMN_AUTO.image(dark = true))
        assertNull(ChatWallpaper.PLAIN.image(dark = true))
        assertEquals(WallpaperImage.AUTUMN_NIGHT, ChatWallpaper.AUTUMN_NIGHT.image(dark = false))
    }
}
