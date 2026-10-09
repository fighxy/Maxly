package app.maxly.data

import app.maxly.domain.Account
import app.maxly.domain.AccountSettings
import app.maxly.domain.BlockedUser
import app.maxly.domain.FamilyProtection
import app.maxly.domain.InactiveTtl
import app.maxly.domain.MiniApp
import app.maxly.domain.MaxlyError
import app.maxly.domain.PrivacyAccess
import app.maxly.domain.PrivacyChange
import app.maxly.domain.TwoFactorStatus
import com.max.core.api.AccountConfig
import com.max.core.api.EntryApp
import com.max.core.api.MaxUser
import com.max.core.api.PrivacyConfig
import com.max.core.api.TwoFactorDetails
import com.max.core.api.WebAppInitData
import com.max.core.api.FamilyProtection as CoreFamily
import com.max.core.api.PrivacyAccess as CoreAccess
import com.max.shared.MaxClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.filterIsInstance

/** Свой профиль, его изменение и настройки приватности. */
interface AccountRepository {
    val account: Flow<Account?>
    val settings: Flow<AccountSettings>
    suspend fun reload()

    /** Свой профиль поменялся на другом устройстве (`NOTIF_PROFILE` 159). */
    val profileChanges: Flow<Unit> get() = kotlinx.coroutines.flow.emptyFlow()

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

    /**
     * Отправляет изменение и возвращает настройки из ответа сервера. Пункты, запертые безопасным
     * режимом или семейной защитой ([AccountSettings.privacyLocked], [AccountSettings.safeModeLocked]),
     * модель сюда не шлёт.
     */
    suspend fun change(change: PrivacyChange): AccountSettings

    suspend fun blockedUsers(): List<BlockedUser>
    suspend fun unblock(userId: String)
    /** Заблокировать пользователя (`CONTACT_UPDATE` 34 `BLOCK`). */
    suspend fun block(userId: String): Unit = throw MaxlyError.Rejected("Заблокировать нельзя")

    /** Пароль для входа и почта восстановления (`AUTH_2FA_DETAILS` 104). */
    suspend fun twoFactorStatus(): TwoFactorStatus

    /** Включить облачный пароль. Почта задаётся отдельно, уже после включения. */
    suspend fun enablePassword(password: String, hint: String?) {}

    /** Сменить облачный пароль: старый, затем новый. */
    suspend fun changePassword(oldPassword: String, newPassword: String) {}

    /** Выключить облачный пароль. */
    suspend fun disablePassword(password: String) {}

    /**
     * Начинает смену почты: новый трек (`AUTH_CREATE_TRACK` 112) и проверка текущего пароля
     * (`AUTH_CHECK_PASSWORD` 113). Возвращает идентификатор трека.
     */
    suspend fun startEmailChange(password: String): String

    /** Шлёт код на [email] (`AUTH_VERIFY_EMAIL` 109). Возвращает секунды до повторной отправки. */
    suspend fun sendEmailCode(trackId: String, email: String): Int

    /**
     * Проверяет код из письма (`AUTH_CHECK_EMAIL` 110), сохраняет почту
     * (`AUTH_SET_2FA` 111, capability 4) и возвращает новый статус.
     */
    suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus

    /**
     * Запуск мини-приложения настроек (`WEB_APP_INIT_DATA` 160).
     * Идентификатор бота берётся из конфига сервера, иначе известный запасной.
     */
    suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp

    /**
     * Возврат внешнего шага на адрес с `externalCallback=1`
     * (`EXTERNAL_CALLBACK` 105, затем новый запуск 160).
     */
    suspend fun miniAppCallback(url: String): MiniApp

    /** Мини-приложение бота (`WEB_APP_INIT_DATA` 160): «Открыть приложение» в чате, кнопка `OPEN_APP`. */
    suspend fun launchBotApp(botId: String, chatId: String?, startParam: String?): MiniApp =
        throw app.maxly.domain.MaxlyError.InvalidRequest
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

    override val profileChanges: Flow<Unit>
        get() = client.events.all.filterIsInstance<com.max.core.events.MaxEvent.ProfileUpdated>().map { }

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

    /**
     * Настройки приватности — проверенным сеттером ядра [MaxClient.setPrivacy] (на нём же стоят
     * `setSearchByPhone`, `setSafeMode` и другие): ключ, значение и замок безопасного режима
     * и семейной защиты проверяет ядро, ответ сервера оно кладёт в `accountConfig`. Остальное
     * (срок неактивности, быстрая реакция) уходит общим `updateUserSettings`.
     */
    override suspend fun change(change: PrivacyChange): AccountSettings = settingsOf(
        MaxCoreGateway.call {
            val privacy = privacyOf(change)
            if (privacy != null) client.setPrivacy(privacy.first, privacy.second) else client.updateUserSettings(valuesOf(change))
        },
    )

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

    override suspend fun block(userId: String) {
        val id = userId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.users.setBlocked(id, true) }
    }

    override suspend fun twoFactorStatus(): TwoFactorStatus = MaxCoreGateway.call {
        statusOf(client.api.twoFactor.status())
    }

    override suspend fun enablePassword(password: String, hint: String?) {
        val trimmed = hint?.trim()?.takeIf { it.isNotEmpty() }
        guarded(TwoFactorErrors::password) { client.api.twoFactor.enable(password, hint = trimmed) }
    }

    override suspend fun changePassword(oldPassword: String, newPassword: String) {
        guarded(TwoFactorErrors::password) { client.api.twoFactor.changePassword(oldPassword, newPassword) }
    }

    override suspend fun disablePassword(password: String) {
        guarded(TwoFactorErrors::password) { client.api.twoFactor.disable(password) }
    }

    override suspend fun startEmailChange(password: String): String = guarded(TwoFactorErrors::password) {
        val track = client.api.twoFactor.createTrack()
        client.api.twoFactor.checkCurrentPassword(track, password)
        track
    }

    override suspend fun sendEmailCode(trackId: String, email: String): Int =
        guarded({ TwoFactorErrors.rejection(it, "Не удалось отправить код. Проверьте адрес почты") }) {
            client.api.twoFactor.sendEmailCode(trackId, email.trim())
        }

    override suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus =
        guarded({ TwoFactorErrors.rejection(it, "Неверный код") }) {
            client.api.twoFactor.confirmEmailCode(trackId, code.trim())
            client.api.twoFactor.commitEmail(trackId)
            statusOf(client.api.twoFactor.status())
        }

    override suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp = MaxCoreGateway.call {
        val entry = when (kind) {
            MiniApp.Kind.SFERUM -> EntryApp.SFERUM
            MiniApp.Kind.DIGITAL_ID -> EntryApp.DIGITAL_ID
        }
        val botId = (client.accountConfig.value ?: AccountConfig()).entryAppBotId(entry)
        miniAppOf(botId, client.api.bots.getWebAppInitData(botId), client.device.deviceId)
    }

    override suspend fun launchBotApp(botId: String, chatId: String?, startParam: String?): MiniApp = MaxCoreGateway.call {
        val bot = botId.toLong()
        miniAppOf(bot, client.api.bots.getWebAppInitData(bot, chatId?.toLongOrNull(), startParam?.takeIf { it.isNotBlank() }), client.device.deviceId)
    }

    override suspend fun miniAppCallback(url: String): MiniApp = MaxCoreGateway.call {
        val next = client.api.bots.externalCallback(url)
        miniAppOf(next.botId, client.api.bots.getWebAppInitData(next.botId, startParam = next.startParam), client.device.deviceId)
    }

    private suspend fun <T> guarded(map: (Throwable) -> MaxlyError, block: suspend () -> T): T = try {
        MaxCoreGateway.call(block)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        throw map(e)
    }

    companion object {
        fun statusOf(details: TwoFactorDetails) = TwoFactorStatus.of(details.enabled, details.email, details.hint)

        fun miniAppOf(botId: Long, data: WebAppInitData, deviceId: String = "") =
            MiniApp(botId, data.url, data.queryId, deviceId)

        private const val BLOCKED_PAGES = 10
        private const val BLOCKED_PAGE_SIZE = 100
        private const val SECONDS_BOUND = 100_000_000_000L

        /** Момент из ответа `PROFILE_DELETE` в миллисекундах: секунды переводятся, ноль и пусто — `null`. */
        fun deletionMillis(timestamp: Long?): Long? = when {
            timestamp == null || timestamp <= 0L -> null
            timestamp < SECONDS_BOUND -> timestamp * 1000
            else -> timestamp
        }

        /**
         * Настройки из `config.user`. Приватность читает ядро ([PrivacyConfig.from], то же, что
         * [MaxClient.privacy]): без ключа — значение по умолчанию веб-клиента MAX (номер видят
         * контакты; найти, позвонить и пригласить могут все), при безопасном режиме — его значения.
         */
        fun settingsOf(config: AccountConfig?): AccountSettings {
            val c = config ?: return AccountSettings()
            val privacy = PrivacyConfig.from(c)
            return AccountSettings(
                known = true,
                phonePrivacy = accessOf(privacy.phoneNumber),
                onlineHidden = privacy.onlineHidden,
                safeMode = privacy.safeMode,
                searchByPhone = accessOf(privacy.searchByPhone),
                incomingCalls = accessOf(privacy.incomingCalls),
                chatInvites = accessOf(privacy.chatInvites),
                safeContentOnly = privacy.safeContentOnly,
                inactiveTtl = InactiveTtl.of(c.userString("INACTIVE_TTL")),
                inviteLink = c.inviteLink?.takeIf { it.isNotBlank() },
                quickReaction = quickReactionOf(c),
                quickReactionEnabled = c.userFlag("DOUBLE_TAP_REACTION_DISABLED") != true,
                familyProtection = familyOf(privacy.familyProtection),
                storiesHistory = c.storiesHistory,
                familyProtectionBotId = c.familyProtectionBotId?.toString(),
            )
        }

        fun accessOf(access: CoreAccess): PrivacyAccess = when (access) {
            CoreAccess.ALL -> PrivacyAccess.ALL
            CoreAccess.CONTACTS -> PrivacyAccess.CONTACTS
            CoreAccess.NOBODY -> PrivacyAccess.NOBODY
        }

        fun coreAccess(access: PrivacyAccess): CoreAccess = when (access) {
            PrivacyAccess.ALL -> CoreAccess.ALL
            PrivacyAccess.CONTACTS -> CoreAccess.CONTACTS
            PrivacyAccess.NOBODY -> CoreAccess.NOBODY
        }

        fun familyOf(value: CoreFamily): FamilyProtection = when (value) {
            CoreFamily.OFF -> FamilyProtection.OFF
            CoreFamily.ADMIN -> FamilyProtection.ADMIN
            CoreFamily.MANAGEABLE -> FamilyProtection.MANAGEABLE
            CoreFamily.UNKNOWN -> FamilyProtection.UNKNOWN
        }

        /**
         * Ключ и значение [MaxClient.setPrivacy] для [change]; `null` — не настройка приватности,
         * она уходит `updateUserSettings`.
         */
        fun privacyOf(change: PrivacyChange): Pair<String, Any>? = when (change) {
            is PrivacyChange.PhonePrivacy -> PrivacyConfig.PHONE_NUMBER_PRIVACY to coreAccess(change.access)
            is PrivacyChange.OnlineHidden -> PrivacyConfig.HIDDEN to change.hidden
            is PrivacyChange.SafeMode -> PrivacyConfig.SAFE_MODE to change.enabled
            is PrivacyChange.SearchByPhone -> PrivacyConfig.SEARCH_BY_PHONE to coreAccess(change.access)
            is PrivacyChange.IncomingCalls -> PrivacyConfig.INCOMING_CALL to coreAccess(change.access)
            is PrivacyChange.ChatInvites -> PrivacyConfig.CHATS_INVITE to coreAccess(change.access)
            is PrivacyChange.SafeContent -> PrivacyConfig.CONTENT_LEVEL_ACCESS to change.safeOnly
            is PrivacyChange.Inactive, is PrivacyChange.QuickReaction -> null
        }

        /**
         * `DOUBLE_TAP_REACTION_VALUE`: строка-эмодзи или карта с `id`.
         * Пустое и неизвестное значение — [AccountSettings.DEFAULT_QUICK_REACTION].
         */
        fun quickReactionOf(config: AccountConfig): String {
            val raw = config.user["DOUBLE_TAP_REACTION_VALUE"]
            val text = when (raw) {
                is String -> raw.trim()
                is Map<*, *> -> ((raw["id"] ?: raw["reaction"]) as? String)?.trim()
                else -> null
            }
            return text?.takeIf { it.isNotEmpty() && it.length <= 32 } ?: AccountSettings.DEFAULT_QUICK_REACTION
        }

        /**
         * Поля `CONFIG`, которые уходят для [change]. Приватность собирает ядро
         * ([PrivacyConfig.payload], как в [MaxClient.setPrivacy]): безопасный режим, как в MAX,
         * при включении заодно ограничивает поиск по номеру, звонки и приглашения контактами
         * и скрывает нежелательный контент, выключение снимает только сам режим.
         */
        fun valuesOf(change: PrivacyChange): Map<String, Any?> = when (change) {
            is PrivacyChange.Inactive -> mapOf("INACTIVE_TTL" to change.ttl.wire)
            is PrivacyChange.QuickReaction -> linkedMapOf(
                "DOUBLE_TAP_REACTION_VALUE" to change.emoji,
                "DOUBLE_TAP_REACTION_DISABLED" to false,
            )
            else -> privacyOf(change)!!.let { (key, value) -> PrivacyConfig.payload(key, value) }
        }

        fun blockedOf(user: MaxUser): BlockedUser = BlockedUser(
            id = user.id.toString(),
            name = user.displayName?.trim().orEmpty().ifEmpty { "Пользователь" },
            phone = user.phone?.takeIf { it > 0 }?.let { "+$it" },
            avatarUrl = user.baseUrl?.takeIf { it.isNotBlank() },
        )
    }
}
