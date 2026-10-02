package app.orbitle.presentation.settings

import app.orbitle.MainDispatcherRule
import app.orbitle.data.AccountRepository
import app.orbitle.data.CoreAccountRepository
import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.InactiveTtl
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PrivacyAccess
import app.orbitle.domain.PrivacyChange
import com.max.core.api.AccountConfig
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private class FakeAccount : AccountRepository {
    val me = MutableStateFlow<Account?>(Account("1", "Иван", "Петров", "+79001234567", null))
    val config = MutableStateFlow(AccountSettings(known = true))
    var gate: CompletableDeferred<Unit>? = null
    var failure: Exception? = null
    val profileCalls = mutableListOf<Triple<String, String, String>>()
    val unblocked = mutableListOf<String>()
    var blocked = listOf(BlockedUser("21", "Бот", null, null), BlockedUser("22", "Пётр", "+79005550011", null))
    var uploaded: ByteArray? = null

    override val account = me
    override val settings = config
    override suspend fun reload() = Unit
    override suspend fun updateProfile(firstName: String, lastName: String, about: String) {
        gate?.await()
        failure?.let { throw it }
        profileCalls += Triple(firstName, lastName, about)
    }
    override suspend fun uploadAvatar(jpeg: ByteArray) {
        failure?.let { throw it }
        uploaded = jpeg
    }
    override suspend fun removeAvatar() {
        failure?.let { throw it }
    }
    override suspend fun change(change: PrivacyChange): AccountSettings {
        gate?.await()
        failure?.let { throw it }
        config.value = config.value.applying(change)
        return config.value
    }
    override suspend fun blockedUsers(): List<BlockedUser> {
        failure?.let { throw it }
        return blocked
    }
    override suspend fun unblock(userId: String) {
        failure?.let { throw it }
        unblocked += userId
    }
}

class AccountSettingsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun `privacy change shows at once and keeps the server value`() {
        val repo = FakeAccount().apply { gate = CompletableDeferred() }
        val model = AccountSettingsViewModel(repo)
        model.setPhonePrivacy(PrivacyAccess.NOBODY)
        assertEquals(PrivacyAccess.NOBODY, model.state.value.settings.phonePrivacy)
        repo.gate!!.complete(Unit)
        assertEquals(PrivacyAccess.NOBODY, model.state.value.settings.phonePrivacy)
        assertNull(model.state.value.error)
    }

    @Test
    fun `failed change rolls back only its own field`() {
        val repo = FakeAccount().apply { gate = CompletableDeferred(); failure = OrbitleError.NetworkUnavailable }
        val model = AccountSettingsViewModel(repo)
        model.setSafeMode(true)
        assertTrue(model.state.value.settings.safeMode)
        // Пока запрос идёт, с сервера пришло другое поле.
        repo.config.value = repo.config.value.copy(inactiveTtl = InactiveTtl.ONE_MONTH, safeMode = true)
        repo.gate!!.complete(Unit)
        val s = model.state.value.settings
        assertFalse(s.safeMode)
        assertEquals(InactiveTtl.ONE_MONTH, s.inactiveTtl)
        assertTrue(model.state.value.error!!.startsWith("Не удалось сохранить настройку"))
    }

    @Test
    fun `same value sends nothing`() {
        val repo = FakeAccount().apply { failure = OrbitleError.Unknown }
        val model = AccountSettingsViewModel(repo)
        model.setOnlineHidden(false)
        assertNull(model.state.value.error)
    }

    @Test
    fun `profile needs a first name and trims fields`() {
        val repo = FakeAccount()
        val model = AccountSettingsViewModel(repo)
        var saved = 0
        model.saveProfile("  ", "Петров", "", onSaved = { saved++ })
        assertEquals("Укажите имя", model.state.value.error)
        assertTrue(repo.profileCalls.isEmpty())
        model.dismissError()
        model.saveProfile(" Иван ", " Сидоров ", " Привет ", onSaved = { saved++ })
        assertEquals(listOf(Triple("Иван", "Сидоров", "Привет")), repo.profileCalls)
        assertEquals(1, saved)
        assertFalse(model.state.value.saving)
    }

    @Test
    fun `profile error keeps the screen open`() {
        val repo = FakeAccount().apply { failure = OrbitleError.Server("x") }
        val model = AccountSettingsViewModel(repo)
        var saved = false
        model.saveProfile("Иван", "", "", onSaved = { saved = true })
        assertFalse(saved)
        assertNotNull(model.state.value.error)
    }

    @Test
    fun `about over the limit is rejected`() {
        val model = AccountSettingsViewModel(FakeAccount())
        assertNotNull(model.validate("Иван", "", "a".repeat(AccountSettingsViewModel.ABOUT_LIMIT + 1)))
        assertNull(model.validate("Иван", "", "a".repeat(AccountSettingsViewModel.ABOUT_LIMIT)))
    }

    @Test
    fun `photo upload error is reported`() {
        val repo = FakeAccount()
        val model = AccountSettingsViewModel(repo)
        model.uploadPhoto(byteArrayOf(1, 2))
        assertEquals(2, repo.uploaded!!.size)
        repo.failure = OrbitleError.NetworkUnavailable
        model.removePhoto()
        assertTrue(model.state.value.error!!.startsWith("Не удалось удалить фото"))
        assertFalse(model.state.value.updatingPhoto)
    }

    @Test
    fun `unblock removes at once and returns on failure`() {
        val repo = FakeAccount()
        val model = AccountSettingsViewModel(repo)
        model.loadBlocked()
        assertEquals(2, model.state.value.blocked!!.size)
        model.unblock(model.state.value.blocked!![1])
        assertEquals(listOf("21"), model.state.value.blocked!!.map { it.id })
        assertEquals(listOf("22"), repo.unblocked)
        repo.failure = OrbitleError.NetworkUnavailable
        model.unblock(model.state.value.blocked!![0])
        assertEquals(listOf("21"), model.state.value.blocked!!.map { it.id })
        assertNotNull(model.state.value.error)
    }

    @Test
    fun `config maps privacy values`() {
        assertFalse(CoreAccountRepository.settingsOf(null).known)
        val s = CoreAccountRepository.settingsOf(
            AccountConfig(user = mapOf("PHONE_NUMBER_PRIVACY" to "_NONE_", "HIDDEN" to true, "SAFE_MODE" to false, "INACTIVE_TTL" to "3m")),
        )
        assertTrue(s.known)
        assertEquals(PrivacyAccess.NOBODY, s.phonePrivacy)
        assertTrue(s.onlineHidden)
        assertEquals(InactiveTtl.THREE_MONTHS, s.inactiveTtl)
    }

    @Test
    fun `safe mode on also limits contacts`() {
        val on = CoreAccountRepository.valuesOf(PrivacyChange.SafeMode(true))
        assertEquals(true, on["SAFE_MODE"])
        assertEquals("CONTACTS", on["INCOMING_CALL"])
        assertEquals(mapOf("SAFE_MODE_NO_PIN" to false, "SAFE_MODE" to false), CoreAccountRepository.valuesOf(PrivacyChange.SafeMode(false)))
        assertEquals(mapOf("INACTIVE_TTL" to "1M"), CoreAccountRepository.valuesOf(PrivacyChange.Inactive(InactiveTtl.ONE_MONTH)))
    }
}
