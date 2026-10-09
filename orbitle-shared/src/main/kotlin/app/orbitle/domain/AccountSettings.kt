package app.orbitle.domain

/**
 * Кто видит номер, кто может звонить и так далее. Подписи — как в MAX. «Никто» уходит на сервер
 * как `NOBODY`, как у веб-клиента MAX.
 */
enum class PrivacyAccess(val wire: String, val title: String) {
    ALL("ALL", "Могут все"),
    CONTACTS("CONTACTS", "Могут контакты"),
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

/**
 * Семейная защита (`FAMILY_PROTECTION`). Включается и выключается только в мини-приложении MAX;
 * здесь — только статус. [MANAGEABLE]: аккаунт под защитой, безопасным режимом и пунктами под ним
 * управляет тот, кто защищает.
 */
enum class FamilyProtection(val title: String) {
    OFF("Выключена"),
    ADMIN("Вы защищаете близкого"),
    MANAGEABLE("Включена — настройками управляет тот, кто вас защищает"),
    UNKNOWN("Неизвестно"),
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

/**
 * Настройки приватности из конфига аккаунта (`config.user`). Значения по умолчанию — те, что
 * берёт веб-клиент MAX, когда ключа нет.
 */
data class AccountSettings(
    /** `false`, пока конфиг не пришёл: экран показывает значения по умолчанию неактивными. */
    val known: Boolean = false,
    /** «Видеть мой номер» (`PHONE_NUMBER_PRIVACY`). */
    val phonePrivacy: PrivacyAccess = PrivacyAccess.CONTACTS,
    /** `true` — статус «в сети» не видит никто, `false` — видят контакты (`HIDDEN`). */
    val onlineHidden: Boolean = false,
    /** Безопасный режим (`SAFE_MODE`): пока включён, четыре пункта ниже заперты, см. [privacyLocked]. */
    val safeMode: Boolean = false,
    /** «Найти меня по номеру» (`SEARCH_BY_PHONE`). */
    val searchByPhone: PrivacyAccess = PrivacyAccess.ALL,
    /** «Позвонить» (`INCOMING_CALL`). */
    val incomingCalls: PrivacyAccess = PrivacyAccess.ALL,
    /** «Пригласить в чат» (`CHATS_INVITE`). */
    val chatInvites: PrivacyAccess = PrivacyAccess.ALL,
    /** «Показывать контент»: `true` — только безопасный (`CONTENT_LEVEL_ACCESS`). */
    val safeContentOnly: Boolean = false,
    val inactiveTtl: InactiveTtl = InactiveTtl.SIX_MONTHS,
    val inviteLink: String? = null,
    /** Эмодзи двойного нажатия (`DOUBLE_TAP_REACTION_VALUE`). Пустого значения у сервера нет — 👍. */
    val quickReaction: String = DEFAULT_QUICK_REACTION,
    /** `false`, когда сервер прислал `DOUBLE_TAP_REACTION_DISABLED`. */
    val quickReactionEnabled: Boolean = true,
    /** Семейная защита: только статус, см. [managedByFamily]. */
    val familyProtection: FamilyProtection = FamilyProtection.OFF,
    /** Пункт «Мои истории» в настройках (`stories-history`). */
    val storiesHistory: Boolean = false,
    /** Бот мини-приложения семейной защиты (`family-protection-botid`); `null` — строка только показывает статус. */
    val familyProtectionBotId: String? = null,
) {
    /** Пункты «Найти меня по номеру», «Позвонить», «Пригласить в чат» и «Показывать контент» не меняются. */
    val lockedBySafeMode: Boolean get() = safeMode

    /**
     * Аккаунт под семейной защитой: безопасный режим и четыре пункта под ним меняет только тот,
     * кто защищает (как `PrivacyConfig.isReadOnly` ядра).
     */
    val managedByFamily: Boolean get() = familyProtection == FamilyProtection.MANAGEABLE

    /** Четыре пункта под безопасным режимом заперты: им или семейной защитой. */
    val privacyLocked: Boolean get() = safeMode || managedByFamily

    /** Сам безопасный режим не переключается: им управляет семейная защита. */
    val safeModeLocked: Boolean get() = managedByFamily

    /** Что показывать в пунктах: при безопасном режиме — его значения, иначе свои. */
    val shownSearchByPhone: PrivacyAccess get() = if (safeMode) PrivacyAccess.CONTACTS else searchByPhone
    val shownIncomingCalls: PrivacyAccess get() = if (safeMode) PrivacyAccess.CONTACTS else incomingCalls
    val shownChatInvites: PrivacyAccess get() = if (safeMode) PrivacyAccess.CONTACTS else chatInvites
    val shownSafeContentOnly: Boolean get() = safeMode || safeContentOnly

    /**
     * Включение безопасного режима заодно ставит его значения четырём пунктам (так же уходит
     * на сервер), выключение снимает только сам режим.
     */
    fun applying(change: PrivacyChange): AccountSettings = when (change) {
        is PrivacyChange.PhonePrivacy -> copy(phonePrivacy = change.access)
        is PrivacyChange.OnlineHidden -> copy(onlineHidden = change.hidden)
        is PrivacyChange.SafeMode -> if (change.enabled) {
            copy(
                safeMode = true,
                searchByPhone = PrivacyAccess.CONTACTS,
                incomingCalls = PrivacyAccess.CONTACTS,
                chatInvites = PrivacyAccess.CONTACTS,
                safeContentOnly = true,
            )
        } else {
            copy(safeMode = false)
        }
        is PrivacyChange.SearchByPhone -> copy(searchByPhone = change.access)
        is PrivacyChange.IncomingCalls -> copy(incomingCalls = change.access)
        is PrivacyChange.ChatInvites -> copy(chatInvites = change.access)
        is PrivacyChange.SafeContent -> copy(safeContentOnly = change.safeOnly)
        is PrivacyChange.Inactive -> copy(inactiveTtl = change.ttl)
        is PrivacyChange.QuickReaction -> copy(quickReaction = change.emoji, quickReactionEnabled = true)
    }

    /** Поле, которое меняет [change], взято из [other]: откат одной настройки. */
    fun restoring(change: PrivacyChange, other: AccountSettings): AccountSettings = when (change) {
        is PrivacyChange.PhonePrivacy -> copy(phonePrivacy = other.phonePrivacy)
        is PrivacyChange.OnlineHidden -> copy(onlineHidden = other.onlineHidden)
        is PrivacyChange.SafeMode -> copy(
            safeMode = other.safeMode,
            searchByPhone = other.searchByPhone,
            incomingCalls = other.incomingCalls,
            chatInvites = other.chatInvites,
            safeContentOnly = other.safeContentOnly,
        )
        is PrivacyChange.SearchByPhone -> copy(searchByPhone = other.searchByPhone)
        is PrivacyChange.IncomingCalls -> copy(incomingCalls = other.incomingCalls)
        is PrivacyChange.ChatInvites -> copy(chatInvites = other.chatInvites)
        is PrivacyChange.SafeContent -> copy(safeContentOnly = other.safeContentOnly)
        is PrivacyChange.Inactive -> copy(inactiveTtl = other.inactiveTtl)
        is PrivacyChange.QuickReaction -> copy(quickReaction = other.quickReaction, quickReactionEnabled = other.quickReactionEnabled)
    }

    companion object {
        const val DEFAULT_QUICK_REACTION = "👍"
    }
}

/** Одно изменение приватности. */
sealed interface PrivacyChange {
    data class PhonePrivacy(val access: PrivacyAccess) : PrivacyChange
    data class OnlineHidden(val hidden: Boolean) : PrivacyChange
    data class SafeMode(val enabled: Boolean) : PrivacyChange
    /** «Найти меня по номеру»: «Могут все» или «Могут контакты». */
    data class SearchByPhone(val access: PrivacyAccess) : PrivacyChange
    /** «Позвонить»: «Могут все» или «Могут контакты». */
    data class IncomingCalls(val access: PrivacyAccess) : PrivacyChange
    /** «Пригласить в чат»: «Могут все» или «Могут контакты». */
    data class ChatInvites(val access: PrivacyAccess) : PrivacyChange
    /** «Показывать контент»: `true` — «Безопасный», `false` — «Весь». */
    data class SafeContent(val safeOnly: Boolean) : PrivacyChange
    data class Inactive(val ttl: InactiveTtl) : PrivacyChange
    /** Быстрая реакция: двойное нажатие ставит этот эмодзи. Заодно включает её, если была выключена. */
    data class QuickReaction(val emoji: String) : PrivacyChange
}

/** Пользователь из чёрного списка. */
data class BlockedUser(
    val id: String,
    val name: String,
    /** Номер в виде `+79991234567`. */
    val phone: String?,
    val avatarUrl: String?,
)
