package app.orbitle.demo

import app.orbitle.data.AccountRepository
import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PrivacyChange
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

/** Свой профиль для DemoActivity; безопасный режим нарочно не сохраняется, чтобы был виден откат. */
class DemoAccount : AccountRepository {
    private val me = MutableStateFlow<Account?>(
        Account("1", "Иван", "Петров", "+79001234567", null, description = "Пишу код и катаюсь на велосипеде"),
    )
    private val config = MutableStateFlow(AccountSettings(known = true))
    private val blocked = mutableListOf(
        BlockedUser("21", "Спам Бот", null, null),
        BlockedUser("22", "Пётр Навязчивый", "+79005550011", null),
    )
    override val account: Flow<Account?> = me
    override val settings: Flow<AccountSettings> = config

    override suspend fun reload() = Unit

    override suspend fun updateProfile(firstName: String, lastName: String, about: String) {
        delay(600)
        me.value = me.value?.copy(firstName = firstName, lastName = lastName, description = about.ifEmpty { null })
    }

    override suspend fun uploadAvatar(jpeg: ByteArray) {
        delay(800)
        me.value = me.value?.copy(hasPhoto = true)
    }

    override suspend fun removeAvatar() {
        delay(500)
        me.value = me.value?.copy(avatarUrl = null, hasPhoto = false)
    }

    override suspend fun change(change: PrivacyChange): AccountSettings {
        delay(700)
        if (change is PrivacyChange.SafeMode) throw OrbitleError.NetworkUnavailable
        config.value = config.value.applying(change)
        return config.value
    }

    override suspend fun blockedUsers(): List<BlockedUser> {
        delay(400)
        return blocked.toList()
    }

    override suspend fun unblock(userId: String) {
        delay(400)
        blocked.removeAll { it.id == userId }
    }
}
