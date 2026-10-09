package app.maxly.presentation.settings

import app.maxly.MainDispatcherRule
import app.maxly.data.AccountRepository
import app.maxly.data.CoreAccountRepository
import app.maxly.domain.Account
import app.maxly.domain.AccountSettings
import app.maxly.domain.BlockedUser
import app.maxly.domain.InactiveTtl
import app.maxly.domain.MiniApp
import app.maxly.domain.OrbitleError
import app.maxly.domain.PrivacyAccess
import app.maxly.domain.PrivacyChange
import app.maxly.domain.TwoFactorStatus
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
    var deletionGate: CompletableDeferred<Unit>? = null
    var deletionFailure: Exception? = null
    var deletionAt: Long? = 1_790_000_000_000L
    var deletionCalls = 0
    override suspend fun requestDeletion(): Long? {
        deletionCalls++
        deletionGate?.await()
        deletionFailure?.let { throw it }
        return deletionAt
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
    override suspend fun twoFactorStatus(): TwoFactorStatus = TwoFactorStatus(false)
    override suspend fun startEmailChange(password: String): String = "track"
    override suspend fun sendEmailCode(trackId: String, email: String): Int = 60
    override suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus = TwoFactorStatus(true)
    override suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp = MiniApp(1, "https://max.ru")
    override suspend fun miniAppCallback(url: String): MiniApp = MiniApp(1, "https://max.ru")
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
    fun `server text wins over our own`() {
        val repo = FakeAccount().apply { failure = app.maxly.data.CoreFailure("SERVER", "profile.name", "raw", "Имя не подходит") }
        val model = AccountSettingsViewModel(repo)
        model.saveProfile("Иван", "", "", onSaved = {})
        assertEquals("Имя не подходит", model.state.value.error)
        // Без текста сервера — свой.
        repo.failure = app.maxly.data.CoreFailure("SERVER", "profile.name")
        model.dismissError()
        model.saveProfile("Иван", "", "", onSaved = {})
        assertEquals("Ошибка сервера (profile.name). Попробуйте позже", model.state.value.error)
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

    @Test
    fun `quick reaction is the account emoji`() {
        val missing = CoreAccountRepository.settingsOf(AccountConfig(user = emptyMap()))
        assertEquals("👍", missing.quickReaction)
        assertTrue(missing.quickReactionEnabled)
        val set = CoreAccountRepository.settingsOf(
            AccountConfig(user = mapOf("DOUBLE_TAP_REACTION_VALUE" to "🔥", "DOUBLE_TAP_REACTION_DISABLED" to true)),
        )
        assertEquals("🔥", set.quickReaction)
        assertFalse(set.quickReactionEnabled)
        val nested = CoreAccountRepository.settingsOf(
            AccountConfig(user = mapOf("DOUBLE_TAP_REACTION_VALUE" to mapOf("id" to "❤️"))),
        )
        assertEquals("❤️", nested.quickReaction)
        assertEquals("👍", CoreAccountRepository.settingsOf(AccountConfig(user = mapOf("DOUBLE_TAP_REACTION_VALUE" to "   "))).quickReaction)
        assertEquals(
            linkedMapOf("DOUBLE_TAP_REACTION_VALUE" to "🔥", "DOUBLE_TAP_REACTION_DISABLED" to false),
            CoreAccountRepository.valuesOf(PrivacyChange.QuickReaction("🔥")),
        )
    }

    @Test
    fun `delete keyword ignores case and surrounding spaces`() {
        assertTrue(AccountSettingsViewModel.isDeleteKeyword("УДАЛИТЬ"))
        assertTrue(AccountSettingsViewModel.isDeleteKeyword("  удалить "))
        assertTrue(AccountSettingsViewModel.isDeleteKeyword("Удалить"))
        assertFalse(AccountSettingsViewModel.isDeleteKeyword(""))
        assertFalse(AccountSettingsViewModel.isDeleteKeyword("удали"))
        assertFalse(AccountSettingsViewModel.isDeleteKeyword("уд алить"))
        assertFalse(AccountSettingsViewModel.isDeleteKeyword("DELETE"))
    }

    @Test
    fun `wrong word sends nothing`() {
        val repo = FakeAccount()
        val model = AccountSettingsViewModel(repo)
        model.deleteAccount("удалит")
        assertEquals(0, repo.deletionCalls)
        assertNull(model.state.value.deleted)
        assertFalse(model.state.value.deleting)
    }

    @Test
    fun `accepted deletion keeps the date and logs out once`() {
        val repo = FakeAccount().apply { deletionGate = CompletableDeferred() }
        val model = AccountSettingsViewModel(repo)
        model.deleteAccount(" удалить ")
        assertTrue(model.state.value.deleting)
        assertNull(model.state.value.deleted)
        repo.deletionGate!!.complete(Unit)
        val s = model.state.value
        assertFalse(s.deleting)
        assertNull(s.deletionError)
        assertEquals(AccountSettingsViewModel.Deletion(1_790_000_000_000L), s.deleted)
        var logouts = 0
        model.finishDeletion { logouts++ }
        model.finishDeletion { logouts++ }
        assertEquals(1, logouts)
        // Модель переживает сеанс: после нового входа окна об удалении нет.
        assertNull(model.state.value.deleted)
    }

    @Test
    fun `deletion without a date is still accepted`() {
        val repo = FakeAccount().apply { deletionAt = null }
        val model = AccountSettingsViewModel(repo)
        model.deleteAccount("УДАЛИТЬ")
        assertEquals(AccountSettingsViewModel.Deletion(null), model.state.value.deleted)
    }

    @Test
    fun `failed deletion shows the error and does not log out`() {
        val repo = FakeAccount().apply { deletionFailure = OrbitleError.NetworkUnavailable }
        val model = AccountSettingsViewModel(repo)
        model.deleteAccount("УДАЛИТЬ")
        val s = model.state.value
        assertFalse(s.deleting)
        assertNull(s.deleted)
        assertTrue(s.deletionError!!.startsWith("Не удалось удалить профиль"))
        assertNull(s.error)
        var logouts = 0
        model.finishDeletion { logouts++ }
        assertEquals(0, logouts)
        // Повтор после ошибки снова отправляет запрос.
        model.dismissDeletionError()
        repo.deletionFailure = null
        model.deleteAccount("УДАЛИТЬ")
        assertEquals(2, repo.deletionCalls)
        assertNotNull(model.state.value.deleted)
    }

    @Test
    fun `double tap sends one deletion request`() {
        val repo = FakeAccount().apply { deletionGate = CompletableDeferred() }
        val model = AccountSettingsViewModel(repo)
        model.deleteAccount("УДАЛИТЬ")
        model.deleteAccount("УДАЛИТЬ")
        assertEquals(1, repo.deletionCalls)
        repo.deletionGate!!.complete(Unit)
        // И после принятого удаления повтор ничего не шлёт.
        model.deleteAccount("УДАЛИТЬ")
        assertEquals(1, repo.deletionCalls)
    }

    @Test
    fun `deletion timestamp is normalized to milliseconds`() {
        assertNull(CoreAccountRepository.deletionMillis(null))
        assertNull(CoreAccountRepository.deletionMillis(0L))
        assertNull(CoreAccountRepository.deletionMillis(-5L))
        assertEquals(1_790_000_000_000L, CoreAccountRepository.deletionMillis(1_790_000_000L))
        assertEquals(1_790_000_000_123L, CoreAccountRepository.deletionMillis(1_790_000_000_123L))
    }

    @Test
    fun `deletion message names the date when known`() {
        val utc = java.time.ZoneOffset.UTC
        // 1 ноября 2026, 12:00 UTC.
        val at = java.time.LocalDateTime.of(2026, 11, 1, 12, 0).toInstant(utc).toEpochMilli()
        assertEquals(
            "Профиль и переписка удалятся 1 ноября 2026. Если войти раньше, удаление отменится. Сейчас вы выйдете из аккаунта.",
            AccountSettingsViewModel.deletionMessage(at, utc),
        )
        assertTrue(AccountSettingsViewModel.deletionMessage(null, utc).startsWith("Через 30 дней профиль и переписка удалятся навсегда."))
    }
}
