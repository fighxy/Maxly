package app.orbitle.data

import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.InactiveTtl
import app.orbitle.domain.PrivacyAccess
import app.orbitle.domain.PrivacyChange
import com.max.core.api.AccountConfig
import com.max.core.api.MaxUser
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** Свой профиль, его изменение и настройки приватности. */
interface AccountRepository {
    val account: Flow<Account?>
    val settings: Flow<AccountSettings>
    suspend fun reload()

    /** Имя, фамилия и «О себе»; пустые фамилия и описание стирают их. */
    suspend fun updateProfile(firstName: String, lastName: String, about: String)
    /** Новое фото профиля (JPEG). */
    suspend fun uploadAvatar(jpeg: ByteArray)
    suspend fun removeAvatar()

    /**
     * Просит сервер удалить профиль. Сервер удаляет его через 30 дней, а вход в этот срок
     * отменяет удаление. Возвращает момент удаления в миллисекундах или `null`, если сервер его не назвал.
     */
    suspend fun requestDeletion(): Long?

    /** Отправляет изменение и возвращает настройки из ответа сервера. */
    suspend fun change(change: PrivacyChange): AccountSettings

    suspend fun blockedUsers(): List<BlockedUser>
    suspend fun unblock(userId: String)
}

class CoreAccountRepository(private val client: MaxClient) : AccountRepository {
    override val account: Flow<Account?> = client.store.state.map { state ->
        val me = state.me ?: return@map null
        val user = state.users[me] ?: return@map Account(me.toString(), "", "", null, null)
        val name = user.names.firstOrNull()
        Account(
            id = me.toString(),
            firstName = name?.firstName?.takeIf { it.isNotBlank() } ?: name?.name.orEmpty(),
            lastName = name?.lastName.orEmpty(),
            phone = user.phone?.let { "+$it" },
            avatarUrl = user.baseUrl?.takeIf { it.isNotBlank() },
            description = user.description?.trim()?.takeIf { it.isNotEmpty() },
            link = user.link?.takeIf { it.isNotBlank() },
            hasPhoto = (user.photoId ?: 0L) > 0L || !user.baseUrl.isNullOrBlank(),
        )
    }.distinctUntilChanged()

    override val settings: Flow<AccountSettings> = client.accountConfig.map(::settingsOf).distinctUntilChanged()

    override suspend fun reload() {
        MaxCoreGateway.call { client.loadMe() }
    }

    override suspend fun updateProfile(firstName: String, lastName: String, about: String) {
        MaxCoreGateway.call { client.updateProfile(firstName.trim(), lastName.trim(), about.trim()) }
    }

    override suspend fun uploadAvatar(jpeg: ByteArray) {
        MaxCoreGateway.call { client.uploadAvatar(jpeg, "avatar.jpg") }
    }

    override suspend fun removeAvatar() {
        MaxCoreGateway.call { client.removeAvatar() }
    }

    override suspend fun requestDeletion(): Long? =
        deletionMillis(MaxCoreGateway.call { client.api.account.requestProfileDeletion(true) })

    override suspend fun change(change: PrivacyChange): AccountSettings =
        settingsOf(MaxCoreGateway.call { client.updateUserSettings(valuesOf(change)) })

    override suspend fun blockedUsers(): List<BlockedUser> = MaxCoreGateway.call {
        val all = ArrayList<MaxUser>()
        var from = 0
        // Страницы по 100; короткая или пустая — последняя.
        for (page in 0 until BLOCKED_PAGES) {
            val users = client.api.users.blockedContacts(from, BLOCKED_PAGE_SIZE)
            all += users
            if (users.size < BLOCKED_PAGE_SIZE) break
            from += users.size
        }
        all.distinctBy { it.id }.map(::blockedOf)
    }

    override suspend fun unblock(userId: String) {
        val id = userId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.users.setBlocked(id, false) }
    }

    companion object {
        private const val BLOCKED_PAGES = 10
        private const val BLOCKED_PAGE_SIZE = 100
        private const val SECONDS_BOUND = 100_000_000_000L

        /** Момент из ответа `PROFILE_DELETE` в миллисекундах: секунды переводятся, ноль и пусто — `null`. */
        fun deletionMillis(timestamp: Long?): Long? = when {
            timestamp == null || timestamp <= 0L -> null
            timestamp < SECONDS_BOUND -> timestamp * 1000
            else -> timestamp
        }

        fun settingsOf(config: AccountConfig?): AccountSettings {
            val c = config ?: return AccountSettings()
            return AccountSettings(
                known = true,
                phonePrivacy = PrivacyAccess.of(c.userString("PHONE_NUMBER_PRIVACY"), PrivacyAccess.ALL),
                onlineHidden = c.userFlag("HIDDEN") ?: false,
                safeMode = c.userFlag("SAFE_MODE") ?: false,
                inactiveTtl = InactiveTtl.of(c.userString("INACTIVE_TTL")),
                inviteLink = c.inviteLink?.takeIf { it.isNotBlank() },
            )
        }

        /**
         * Поля `CONFIG` для изменения. Безопасный режим, как в Max: включение заодно
         * ограничивает поиск по номеру, звонки и приглашения контактами и скрывает
         * нежелательный контент; выключение снимает только сам режим.
         */
        fun valuesOf(change: PrivacyChange): Map<String, Any?> = when (change) {
            is PrivacyChange.PhonePrivacy -> mapOf("PHONE_NUMBER_PRIVACY" to change.access.wire)
            is PrivacyChange.OnlineHidden -> mapOf("HIDDEN" to change.hidden)
            is PrivacyChange.Inactive -> mapOf("INACTIVE_TTL" to change.ttl.wire)
            is PrivacyChange.SafeMode -> if (change.enabled) {
                linkedMapOf(
                    "INCOMING_CALL" to "CONTACTS", "SEARCH_BY_PHONE" to "CONTACTS", "SAFE_MODE_NO_PIN" to true,
                    "CONTENT_LEVEL_ACCESS" to true, "CHATS_INVITE" to "CONTACTS", "SAFE_MODE" to true,
                )
            } else {
                linkedMapOf("SAFE_MODE_NO_PIN" to false, "SAFE_MODE" to false)
            }
        }

        fun blockedOf(user: MaxUser): BlockedUser = BlockedUser(
            id = user.id.toString(),
            name = user.displayName?.trim().orEmpty().ifEmpty { "Пользователь" },
            phone = user.phone?.takeIf { it > 0 }?.let { "+$it" },
            avatarUrl = user.baseUrl?.takeIf { it.isNotBlank() },
        )
    }
}
