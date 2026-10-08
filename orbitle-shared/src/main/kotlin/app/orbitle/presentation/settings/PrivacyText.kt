package app.orbitle.presentation.settings

import app.orbitle.domain.PrivacyAccess

/** Подписи «Конфиденциальности» — как в разделе «Безопасность» MAX. */
object PrivacyText {
    const val SAFE_MODE = "Безопасный режим"
    const val SAFE_MODE_DESCRIPTION =
        "Найти по номеру, позвонить и пригласить в чат смогут только контакты, контент — только безопасный"

    /** Под запертыми пунктами, пока включён безопасный режим. */
    const val SAFE_MODE_LOCK =
        "Пока включён безопасный режим, эти пункты не меняются. Чтобы выбрать другое, выключите безопасный режим."

    const val SEARCH_BY_PHONE = "Найти меня по номеру"
    const val SEARCH_BY_PHONE_DESCRIPTION = "Кто может найти меня по номеру телефона"
    const val INCOMING_CALL = "Позвонить"
    const val INCOMING_CALL_DESCRIPTION = "Кто может мне звонить"
    const val CHATS_INVITE = "Пригласить в чат"
    const val CHATS_INVITE_DESCRIPTION = "Кто может пригласить меня в чат"
    const val CONTENT = "Показывать контент"
    const val CONTENT_DESCRIPTION = "Безопасный — без материалов 16+ и 18+, в том числе в поиске и рекомендациях"

    const val INFORMATION = "Информация"
    const val ONLINE = "Видеть статус «в сети»"
    const val ONLINE_DESCRIPTION = "Кто может видеть, когда я в сети. Если выбрать «Никто», вы тоже не будете видеть, кто в сети."
    const val PHONE = "Видеть мой номер"
    const val PHONE_DESCRIPTION = "Кто может видеть мой номер телефона"

    const val BLACKLIST = "Чёрный список"
    const val BLACKLIST_DESCRIPTION = "Список тех, кто не может вам писать, звонить и добавлять в чаты"

    /** Варианты «Найти меня по номеру», «Позвонить» и «Пригласить в чат»: «Никто» в MAX здесь нет. */
    val twoWay: List<PrivacyAccess> = listOf(PrivacyAccess.ALL, PrivacyAccess.CONTACTS)

    fun content(safeOnly: Boolean): String = if (safeOnly) "Безопасный" else "Весь"

    fun online(hidden: Boolean): String = if (hidden) "Никто" else "Контакты"

    /** Пояснение варианта «Найти меня по номеру». */
    fun searchByPhoneHint(access: PrivacyAccess): String? = when (access) {
        PrivacyAccess.ALL -> "Любой, кто сохранил ваш номер в телефонной книге, сможет найти вас в MAX"
        PrivacyAccess.CONTACTS -> "Только тот, кто есть в ваших контактах и сохранил ваш номер в телефонной книге, сможет найти вас в MAX"
        PrivacyAccess.NOBODY -> null
    }
}
