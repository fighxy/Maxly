package app.orbitle.presentation.settings

import app.orbitle.data.AccountLimitsStore
import app.orbitle.data.PreferenceStore
import app.orbitle.domain.AccountLimits
import app.orbitle.domain.AuthPhase
import app.orbitle.domain.freshEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset
import java.time.ZonedDateTime

class AccountLimitsTest {
    private val zone = ZoneOffset.ofHours(3)
    private val text = AccountLimitsText(zone)
    private val hour = 3_600_000L

    private fun at(day: Int, hour: Int, minute: Int = 0): Long =
        ZonedDateTime.of(2026, 10, day, hour, minute, 0, 0, zone).toInstant().toEpochMilli()

    private class MapStore(val values: MutableMap<String, String> = mutableMapOf()) : PreferenceStore {
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) {
            values[key] = value
        }
    }

    @Test
    fun loginLimitsLastAboutADay() {
        val granted = at(4, 14, 30)
        val limits = AccountLimits(AccountLimits.Entry.LOGIN, granted)
        assertEquals(granted + 24 * hour, limits.liftsAtMs)
        assertTrue(limits.isActive(granted + 23 * hour))
        assertFalse(limits.isActive(granted + 24 * hour))
        assertTrue(limits.needsNotice(granted + hour))
        assertFalse(limits.copy(shown = true).needsNotice(granted + hour))
        // Приложение не открывали больше суток: панель уже ни к чему.
        assertFalse(limits.needsNotice(granted + 25 * hour))
    }

    @Test
    fun registrationLimitsHaveNoDeadline() {
        val limits = AccountLimits(AccountLimits.Entry.REGISTRATION, at(4, 10))
        assertNull(limits.liftsAtMs)
        assertFalse(limits.isActive(at(4, 11)))
        assertTrue(limits.needsNotice(at(9, 11)))
        assertFalse(limits.copy(shown = true).needsNotice(at(4, 11)))
    }

    @Test
    fun freshEntryFollowsTheLoginStep() {
        assertEquals(AccountLimits.Entry.LOGIN, AuthPhase.CodeSent(6).freshEntry())
        assertEquals(AccountLimits.Entry.LOGIN, AuthPhase.Password("подсказка").freshEntry())
        assertEquals(AccountLimits.Entry.REGISTRATION, AuthPhase.Registration.freshEntry())
        assertNull(AuthPhase.Restoring.freshEntry())
        assertNull(AuthPhase.SignedOut.freshEntry())
        assertNull(AuthPhase.Expired().freshEntry())
        assertNull(AuthPhase.SignedIn("1").freshEntry())
    }

    @Test
    fun storeSurvivesRestartAndForgetsOnClear() {
        val prefs = MapStore()
        var now = at(4, 14, 30)
        val store = AccountLimitsStore(prefs) { now }
        assertNull(store.state.value)

        store.grant(AccountLimits.Entry.LOGIN)
        assertEquals(AccountLimits(AccountLimits.Entry.LOGIN, at(4, 14, 30)), store.state.value)
        assertEquals(store.state.value, AccountLimitsStore(prefs).state.value)

        now = at(4, 15)
        store.markShown()
        val shown = AccountLimitsStore(prefs).state.value
        assertEquals(true, shown?.shown)
        assertEquals(at(4, 14, 30), shown?.grantedAtMs)

        store.clear()
        assertNull(store.state.value)
        assertNull(AccountLimitsStore(prefs).state.value)
    }

    @Test
    fun newLoginReplacesTheShownMark() {
        var now = at(4, 9)
        val store = AccountLimitsStore(MapStore()) { now }
        store.grant(AccountLimits.Entry.REGISTRATION)
        store.markShown()
        now = at(6, 18)
        store.grant(AccountLimits.Entry.LOGIN)
        assertEquals(AccountLimits(AccountLimits.Entry.LOGIN, at(6, 18)), store.state.value)
    }

    @Test
    fun unknownStoredValueMeansNoLimits() {
        assertNull(AccountLimitsStore.decode(null))
        assertNull(AccountLimitsStore.decode(""))
        assertNull(AccountLimitsStore.decode("login"))
        assertNull(AccountLimitsStore.decode("guest 1790000000000 0"))
        assertNull(AccountLimitsStore.decode("login soon 0"))
        assertEquals(
            AccountLimits(AccountLimits.Entry.REGISTRATION, 1_790_000_000_000L, shown = true),
            AccountLimitsStore.decode(AccountLimitsStore.encode(AccountLimits(AccountLimits.Entry.REGISTRATION, 1_790_000_000_000L, shown = true))),
        )
    }

    @Test
    fun loginContentNamesTheLiftTime() {
        val limits = AccountLimits(AccountLimits.Entry.LOGIN, at(4, 14, 30))
        val content = text.content(limits, at(4, 14, 31))
        assertEquals("Аккаунт временно ограничен", content.title)
        assertTrue(content.message, content.message.endsWith("Ограничения снимутся примерно завтра в 14:30."))
        assertEquals(
            listOf(AccountLimitsContent.Icon.PASSWORD, AccountLimitsContent.Icon.SESSIONS),
            content.items.map { it.icon },
        )
        val late = text.content(limits, at(5, 15))
        assertTrue(late.message, late.message.endsWith("Ограничения уже должны были сняться."))
    }

    @Test
    fun registrationContentListsPossibleLimits() {
        val content = text.content(AccountLimits(AccountLimits.Entry.REGISTRATION, at(4, 10)), at(4, 10))
        assertEquals("Аккаунт может быть ограничен", content.title)
        assertEquals(
            listOf(AccountLimitsContent.Icon.MESSAGES, AccountLimitsContent.Icon.GROUPS, AccountLimitsContent.Icon.OTHER),
            content.items.map { it.icon },
        )
    }

    @Test
    fun settingsRowOnlyWhileLoginLimitsLast() {
        val limits = AccountLimits(AccountLimits.Entry.LOGIN, at(4, 14, 30), shown = true)
        assertEquals(
            AccountLimitsRow("Аккаунт временно ограничен", "Снимутся примерно завтра в 14:30"),
            text.row(limits, at(4, 20)),
        )
        assertEquals("Снимутся примерно сегодня в 14:30", text.row(limits, at(5, 8))?.subtitle)
        assertNull(text.row(limits, at(5, 14, 30)))
        assertNull(text.row(AccountLimits(AccountLimits.Entry.REGISTRATION, at(4, 10)), at(4, 11)))
        assertNull(text.row(null, at(4, 11)))
    }

    @Test
    fun momentFarAheadUsesTheDate() {
        assertEquals("сегодня в 09:05", text.moment(at(4, 9, 5), at(4, 1)))
        assertEquals("6 октября в 10:00", text.moment(at(6, 10), at(4, 1)))
    }
}
