package app.orbitle.presentation.settings

import app.orbitle.MainDispatcherRule
import app.orbitle.data.AccountRepository
import app.orbitle.data.CoreAccountRepository
import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.FamilyProtection
import app.orbitle.domain.MiniApp
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PrivacyAccess
import app.orbitle.domain.PrivacyChange
import app.orbitle.domain.TwoFactorStatus
import com.max.core.api.AccountConfig
import com.max.core.api.PrivacyConfig
import com.max.core.api.PrivacyAccess as CoreAccess
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Пункты приватности MAX: значения по умолчанию, ключи, сеттеры ядра, замки безопасного режима и семейной защиты. */
class MaxPrivacySettingsTest {
    @get:Rule val main = MainDispatcherRule()

    /** Аккаунт для приватности: копит изменения, остальное не используется. */
    private class PrivacyAccount(initial: AccountSettings = AccountSettings(known = true)) : AccountRepository {
        override val account = MutableStateFlow<Account?>(null)
        override val settings = MutableStateFlow(initial)
        val changes = mutableListOf<PrivacyChange>()
        var gate: CompletableDeferred<Unit>? = null
        var failure: Exception? = null
        var blocked: List<BlockedUser> = emptyList()

        override suspend fun change(change: PrivacyChange): AccountSettings {
            changes += change
            gate?.await()
            failure?.let { throw it }
            settings.value = settings.value.applying(change)
            return settings.value
        }

        override suspend fun blockedUsers(): List<BlockedUser> {
            failure?.let { throw it }
            return blocked
        }

        override suspend fun reload() = Unit
        override suspend fun updateProfile(firstName: String, lastName: String, about: String) = Unit
        override suspend fun uploadAvatar(jpeg: ByteArray) = Unit
        override suspend fun removeAvatar() = Unit
        override suspend fun requestDeletion(): Long? = null
        override suspend fun unblock(userId: String) = Unit
        override suspend fun twoFactorStatus(): TwoFactorStatus = TwoFactorStatus(false)
        override suspend fun startEmailChange(password: String): String = "track"
        override suspend fun sendEmailCode(trackId: String, email: String): Int = 60
        override suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus = TwoFactorStatus(true)
        override suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp = MiniApp(1, "https://max.ru")
        override suspend fun miniAppCallback(url: String): MiniApp = MiniApp(1, "https://max.ru")
    }

    @Test
    fun `missing keys read as the MAX web defaults`() {
        for (s in listOf(AccountSettings(), CoreAccountRepository.settingsOf(AccountConfig(user = emptyMap())))) {
            assertEquals(PrivacyAccess.CONTACTS, s.phonePrivacy)
            assertEquals(PrivacyAccess.ALL, s.searchByPhone)
            assertEquals(PrivacyAccess.ALL, s.incomingCalls)
            assertEquals(PrivacyAccess.ALL, s.chatInvites)
            assertFalse(s.safeContentOnly)
            assertFalse(s.onlineHidden)
            assertFalse(s.safeMode)
        }
    }

    @Test
    fun `config keys of the four items are read, none in any spelling`() {
        val s = CoreAccountRepository.settingsOf(
            AccountConfig(
                user = mapOf(
                    "SEARCH_BY_PHONE" to "CONTACTS",
                    "INCOMING_CALL" to "contacts",
                    "CHATS_INVITE" to "_NONE_",
                    "CONTENT_LEVEL_ACCESS" to true,
                    "PHONE_NUMBER_PRIVACY" to "ALL",
                ),
            ),
        )
        assertEquals(PrivacyAccess.CONTACTS, s.searchByPhone)
        assertEquals(PrivacyAccess.CONTACTS, s.incomingCalls)
        assertEquals(PrivacyAccess.NOBODY, s.chatInvites)
        assertTrue(s.safeContentOnly)
        assertEquals(PrivacyAccess.ALL, s.phonePrivacy)
        // Незнакомое значение — значение по умолчанию.
        assertEquals(PrivacyAccess.ALL, CoreAccountRepository.settingsOf(AccountConfig(user = mapOf("SEARCH_BY_PHONE" to "FRIENDS"))).searchByPhone)
    }

    @Test
    fun `each item goes under its own key and nobody is sent as NOBODY`() {
        assertEquals(mapOf("SEARCH_BY_PHONE" to "CONTACTS"), CoreAccountRepository.valuesOf(PrivacyChange.SearchByPhone(PrivacyAccess.CONTACTS)))
        assertEquals(mapOf("INCOMING_CALL" to "ALL"), CoreAccountRepository.valuesOf(PrivacyChange.IncomingCalls(PrivacyAccess.ALL)))
        assertEquals(mapOf("CHATS_INVITE" to "CONTACTS"), CoreAccountRepository.valuesOf(PrivacyChange.ChatInvites(PrivacyAccess.CONTACTS)))
        assertEquals(mapOf("CONTENT_LEVEL_ACCESS" to true), CoreAccountRepository.valuesOf(PrivacyChange.SafeContent(true)))
        assertEquals(mapOf("PHONE_NUMBER_PRIVACY" to "NOBODY"), CoreAccountRepository.valuesOf(PrivacyChange.PhonePrivacy(PrivacyAccess.NOBODY)))
    }

    @Test
    fun `privacy changes go to the checked core setter under their keys`() {
        assertEquals(PrivacyConfig.SEARCH_BY_PHONE to CoreAccess.CONTACTS, CoreAccountRepository.privacyOf(PrivacyChange.SearchByPhone(PrivacyAccess.CONTACTS)))
        assertEquals(PrivacyConfig.INCOMING_CALL to CoreAccess.ALL, CoreAccountRepository.privacyOf(PrivacyChange.IncomingCalls(PrivacyAccess.ALL)))
        assertEquals(PrivacyConfig.CHATS_INVITE to CoreAccess.CONTACTS, CoreAccountRepository.privacyOf(PrivacyChange.ChatInvites(PrivacyAccess.CONTACTS)))
        assertEquals(PrivacyConfig.CONTENT_LEVEL_ACCESS to true, CoreAccountRepository.privacyOf(PrivacyChange.SafeContent(true)))
        assertEquals(PrivacyConfig.PHONE_NUMBER_PRIVACY to CoreAccess.NOBODY, CoreAccountRepository.privacyOf(PrivacyChange.PhonePrivacy(PrivacyAccess.NOBODY)))
        assertEquals(PrivacyConfig.HIDDEN to true, CoreAccountRepository.privacyOf(PrivacyChange.OnlineHidden(true)))
        assertEquals(PrivacyConfig.SAFE_MODE to false, CoreAccountRepository.privacyOf(PrivacyChange.SafeMode(false)))
        // Не приватность: общий updateUserSettings.
        assertNull(CoreAccountRepository.privacyOf(PrivacyChange.Inactive(app.orbitle.domain.InactiveTtl.ONE_MONTH)))
        assertNull(CoreAccountRepository.privacyOf(PrivacyChange.QuickReaction("🔥")))
    }

    @Test
    fun `access maps to the core and back, nobody included`() {
        for (access in PrivacyAccess.entries) {
            assertEquals(access, CoreAccountRepository.accessOf(CoreAccountRepository.coreAccess(access)))
            assertEquals(access.wire, CoreAccountRepository.coreAccess(access).wire)
        }
        assertEquals(PrivacyAccess.NOBODY, CoreAccountRepository.accessOf(CoreAccess.NOBODY))
    }

    @Test
    fun `safe mode from the server reports its forced values`() {
        val s = CoreAccountRepository.settingsOf(
            AccountConfig(user = mapOf("SAFE_MODE" to true, "SEARCH_BY_PHONE" to "ALL", "INCOMING_CALL" to "ALL", "CHATS_INVITE" to "ALL")),
        )
        assertTrue(s.safeMode)
        assertTrue(s.privacyLocked)
        assertFalse(s.safeModeLocked)
        assertEquals(PrivacyAccess.CONTACTS, s.searchByPhone)
        assertEquals(PrivacyAccess.CONTACTS, s.incomingCalls)
        assertEquals(PrivacyAccess.CONTACTS, s.chatInvites)
        assertTrue(s.safeContentOnly)
    }

    @Test
    fun `family protection status is read from the config`() {
        fun family(raw: Any?) = CoreAccountRepository.settingsOf(AccountConfig(user = if (raw == null) emptyMap() else mapOf("FAMILY_PROTECTION" to raw))).familyProtection
        assertEquals(FamilyProtection.OFF, family(null))
        assertEquals(FamilyProtection.OFF, family("OFF"))
        assertEquals(FamilyProtection.ADMIN, family("ADMIN"))
        assertEquals(FamilyProtection.MANAGEABLE, family("manageable"))
        assertEquals(FamilyProtection.UNKNOWN, family("SOMETHING"))
        assertEquals("Выключена", FamilyProtection.OFF.title)
        assertEquals("Неизвестно", FamilyProtection.UNKNOWN.title)
    }

    @Test
    fun `locks match the read-only keys of the core`() {
        val locked = listOf(PrivacyConfig.SEARCH_BY_PHONE, PrivacyConfig.INCOMING_CALL, PrivacyConfig.CHATS_INVITE, PrivacyConfig.CONTENT_LEVEL_ACCESS)
        for (family in listOf("OFF", "ADMIN", "MANAGEABLE", "X")) {
            for (safe in listOf(false, true)) {
                val config = AccountConfig(user = mapOf("FAMILY_PROTECTION" to family, "SAFE_MODE" to safe))
                val core = PrivacyConfig.from(config)
                val ours = CoreAccountRepository.settingsOf(config)
                for (key in locked) assertEquals("$family/$safe $key", core.isReadOnly(key), ours.privacyLocked)
                assertEquals("$family/$safe", core.isReadOnly(PrivacyConfig.SAFE_MODE), ours.safeModeLocked)
                assertFalse(core.isReadOnly(PrivacyConfig.HIDDEN))
                assertFalse(core.isReadOnly(PrivacyConfig.PHONE_NUMBER_PRIVACY))
            }
        }
    }

    @Test
    fun `the core refuses a locked key as well`() {
        val managed = PrivacyConfig.from(AccountConfig(user = mapOf("FAMILY_PROTECTION" to "MANAGEABLE")))
        val (key, value) = CoreAccountRepository.privacyOf(PrivacyChange.IncomingCalls(PrivacyAccess.ALL))!!
        assertTrue(runCatching { PrivacyConfig.payload(key, value, managed) }.exceptionOrNull() is IllegalStateException)
        assertEquals(mapOf("HIDDEN" to true), PrivacyConfig.payload(PrivacyConfig.HIDDEN, true, managed))
    }

    @Test
    fun `family protection locks safe mode and the four items, information stays open`() {
        val repo = PrivacyAccount(AccountSettings(known = true, familyProtection = FamilyProtection.MANAGEABLE))
        val model = AccountSettingsViewModel(repo)
        val s = model.state.value.settings
        assertTrue(s.privacyLocked)
        assertTrue(s.safeModeLocked)
        assertFalse(s.lockedBySafeMode)
        model.setSafeMode(true)
        model.setSearchByPhone(PrivacyAccess.CONTACTS)
        model.setIncomingCalls(PrivacyAccess.CONTACTS)
        model.setChatInvites(PrivacyAccess.CONTACTS)
        model.setSafeContentOnly(true)
        assertTrue(repo.changes.isEmpty())
        assertFalse(model.state.value.settings.safeMode)
        model.setOnlineHidden(true)
        model.setPhonePrivacy(PrivacyAccess.NOBODY)
        assertEquals(listOf(PrivacyChange.OnlineHidden(true), PrivacyChange.PhonePrivacy(PrivacyAccess.NOBODY)), repo.changes)
        assertEquals(PrivacyText.FAMILY_LOCK, PrivacyText.lockNote(model.state.value.settings))
    }

    @Test
    fun `lock note names what holds the lock`() {
        assertNull(PrivacyText.lockNote(AccountSettings(known = true)))
        assertNull(PrivacyText.lockNote(AccountSettings(known = true, familyProtection = FamilyProtection.ADMIN)))
        assertEquals(PrivacyText.SAFE_MODE_LOCK, PrivacyText.lockNote(AccountSettings(known = true, safeMode = true)))
        assertEquals(PrivacyText.FAMILY_LOCK, PrivacyText.lockNote(AccountSettings(known = true, safeMode = true, familyProtection = FamilyProtection.MANAGEABLE)))
    }

    @Test
    fun `unlocked items change at once and reach the repository`() {
        val repo = PrivacyAccount()
        val model = AccountSettingsViewModel(repo)
        model.setSearchByPhone(PrivacyAccess.CONTACTS)
        model.setIncomingCalls(PrivacyAccess.CONTACTS)
        model.setChatInvites(PrivacyAccess.CONTACTS)
        model.setSafeContentOnly(true)
        val s = model.state.value.settings
        assertEquals(PrivacyAccess.CONTACTS, s.searchByPhone)
        assertEquals(PrivacyAccess.CONTACTS, s.incomingCalls)
        assertEquals(PrivacyAccess.CONTACTS, s.chatInvites)
        assertTrue(s.safeContentOnly)
        assertEquals(4, repo.changes.size)
    }

    @Test
    fun `safe mode forces the four items and locks them`() {
        val repo = PrivacyAccount()
        val model = AccountSettingsViewModel(repo)
        model.setSafeMode(true)
        val s = model.state.value.settings
        assertTrue(s.lockedBySafeMode)
        assertEquals(PrivacyAccess.CONTACTS, s.shownSearchByPhone)
        assertEquals(PrivacyAccess.CONTACTS, s.shownIncomingCalls)
        assertEquals(PrivacyAccess.CONTACTS, s.shownChatInvites)
        assertTrue(s.shownSafeContentOnly)
        model.setSearchByPhone(PrivacyAccess.ALL)
        model.setIncomingCalls(PrivacyAccess.ALL)
        model.setChatInvites(PrivacyAccess.ALL)
        model.setSafeContentOnly(false)
        assertEquals(listOf<PrivacyChange>(PrivacyChange.SafeMode(true)), repo.changes)
        assertEquals(PrivacyAccess.CONTACTS, model.state.value.settings.searchByPhone)
    }

    @Test
    fun `information items stay open under safe mode`() {
        val repo = PrivacyAccount(AccountSettings(known = true, safeMode = true))
        val model = AccountSettingsViewModel(repo)
        model.setOnlineHidden(true)
        model.setPhonePrivacy(PrivacyAccess.NOBODY)
        assertTrue(model.state.value.settings.onlineHidden)
        assertEquals(PrivacyAccess.NOBODY, model.state.value.settings.phonePrivacy)
        assertEquals(2, repo.changes.size)
    }

    @Test
    fun `server safe mode shows forced values over the stored ones, off unlocks them`() {
        val stored = AccountSettings(known = true, safeMode = true, searchByPhone = PrivacyAccess.ALL, incomingCalls = PrivacyAccess.ALL)
        val repo = PrivacyAccount(stored)
        val model = AccountSettingsViewModel(repo)
        assertEquals(PrivacyAccess.CONTACTS, model.state.value.settings.shownSearchByPhone)
        assertEquals(PrivacyAccess.ALL, model.state.value.settings.searchByPhone)
        model.setSafeMode(false)
        val s = model.state.value.settings
        assertFalse(s.lockedBySafeMode)
        // Выключение снимает только сам режим: пункты показывают свои значения.
        assertEquals(PrivacyAccess.ALL, s.shownSearchByPhone)
        assertFalse(s.shownSafeContentOnly)
        model.setIncomingCalls(PrivacyAccess.CONTACTS)
        assertEquals(PrivacyAccess.CONTACTS, model.state.value.settings.incomingCalls)
        assertEquals(listOf(PrivacyChange.SafeMode(false), PrivacyChange.IncomingCalls(PrivacyAccess.CONTACTS)), repo.changes)
    }

    @Test
    fun `failed safe mode rolls back the four items too`() {
        val repo = PrivacyAccount().apply { gate = CompletableDeferred(); failure = OrbitleError.NetworkUnavailable }
        val model = AccountSettingsViewModel(repo)
        model.setSafeMode(true)
        assertEquals(PrivacyAccess.CONTACTS, model.state.value.settings.searchByPhone)
        repo.gate!!.complete(Unit)
        val s = model.state.value.settings
        assertFalse(s.safeMode)
        assertEquals(PrivacyAccess.ALL, s.searchByPhone)
        assertEquals(PrivacyAccess.ALL, s.incomingCalls)
        assertEquals(PrivacyAccess.ALL, s.chatInvites)
        assertFalse(s.safeContentOnly)
        assertTrue(model.state.value.error!!.startsWith("Не удалось сохранить настройку"))
    }

    @Test
    fun `nothing is sent before the config arrives`() {
        val repo = PrivacyAccount(AccountSettings())
        val model = AccountSettingsViewModel(repo)
        model.setSearchByPhone(PrivacyAccess.CONTACTS)
        model.setSafeContentOnly(true)
        assertTrue(repo.changes.isEmpty())
    }

    @Test
    fun `blacklist counter loads quietly`() {
        val repo = PrivacyAccount().apply { blocked = listOf(BlockedUser("21", "Бот", null, null)) }
        val model = AccountSettingsViewModel(repo)
        model.countBlocked()
        assertEquals(1, model.state.value.blocked?.size)
        repo.failure = OrbitleError.NetworkUnavailable
        val offline = AccountSettingsViewModel(repo)
        offline.countBlocked()
        assertNull(offline.state.value.blocked)
        assertNull(offline.state.value.error)
    }

    @Test
    fun `two-way items offer no nobody, as in MAX`() {
        assertEquals(listOf(PrivacyAccess.ALL, PrivacyAccess.CONTACTS), PrivacyText.twoWay)
        assertEquals("Могут все", PrivacyAccess.ALL.title)
        assertEquals("Могут контакты", PrivacyAccess.CONTACTS.title)
        assertEquals("Безопасный", PrivacyText.content(true))
        assertEquals("Контакты", PrivacyText.online(false))
    }
}
