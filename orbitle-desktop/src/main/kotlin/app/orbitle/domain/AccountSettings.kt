package app.orbitle.domain

/** Кто видит номер, кто может звонить и так далее. */
enum class PrivacyAccess(val wire: String, val title: String) {
    ALL("ALL", "Все"),
    CONTACTS("CONTACTS", "Мои контакты"),
    NOBODY("NOBODY", "Никто");

    companion object {
        /** `_NONE_` и `NONE` у сервера тоже значат «никто». */
        fun of(value: String?, fallback: PrivacyAccess): PrivacyAccess = when (value?.uppercase()) {
            "ALL" -> ALL
            "CONTACTS" -> CONTACTS
            "NOBODY", "_NONE_", "NONE" -> NOBODY
            else -> fallback
        }
    }
}

/** Через сколько месяцев без входа аккаунт удаляется. */
enum class InactiveTtl(val wire: String, val title: String) {
    ONE_MONTH("1M", "1 месяц"),
    THREE_MONTHS("3M", "3 месяца"),
    SIX_MONTHS("6M", "6 месяцев");

    companion object {
        fun of(value: String?): InactiveTtl = entries.firstOrNull { it.wire == value?.uppercase() } ?: SIX_MONTHS
    }
}

/** Настройки приватности из конфига аккаунта. */
data class AccountSettings(
    /** `false`, пока конфиг не пришёл: экран показывает значения по умолчанию неактивными. */
    val known: Boolean = false,
    val phonePrivacy: PrivacyAccess = PrivacyAccess.ALL,
    /** `true` — статус «в сети» не видит никто, `false` — видят контакты. */
    val onlineHidden: Boolean = false,
    val safeMode: Boolean = false,
    val inactiveTtl: InactiveTtl = InactiveTtl.SIX_MONTHS,
    val inviteLink: String? = null,
) {
    fun applying(change: PrivacyChange): AccountSettings = when (change) {
        is PrivacyChange.PhonePrivacy -> copy(phonePrivacy = change.access)
        is PrivacyChange.OnlineHidden -> copy(onlineHidden = change.hidden)
        is PrivacyChange.SafeMode -> copy(safeMode = change.enabled)
        is PrivacyChange.Inactive -> copy(inactiveTtl = change.ttl)
    }

    /** Поле, которое меняет [change], взято из [other]: откат одной настройки. */
    fun restoring(change: PrivacyChange, other: AccountSettings): AccountSettings = when (change) {
        is PrivacyChange.PhonePrivacy -> copy(phonePrivacy = other.phonePrivacy)
        is PrivacyChange.OnlineHidden -> copy(onlineHidden = other.onlineHidden)
        is PrivacyChange.SafeMode -> copy(safeMode = other.safeMode)
        is PrivacyChange.Inactive -> copy(inactiveTtl = other.inactiveTtl)
    }
}

/** Одно изменение приватности. */
sealed interface PrivacyChange {
    data class PhonePrivacy(val access: PrivacyAccess) : PrivacyChange
    data class OnlineHidden(val hidden: Boolean) : PrivacyChange
    data class SafeMode(val enabled: Boolean) : PrivacyChange
    data class Inactive(val ttl: InactiveTtl) : PrivacyChange
}

/** Пользователь из чёрного списка. */
data class BlockedUser(
    val id: String,
    val name: String,
    /** Номер в виде `+79991234567`. */
    val phone: String?,
    val avatarUrl: String?,
)
