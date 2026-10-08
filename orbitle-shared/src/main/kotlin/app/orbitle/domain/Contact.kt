package app.orbitle.domain

import com.max.core.api.ContactNames
import com.max.core.api.PhoneNumbers

/** Контакт аккаунта с последним известным присутствием. */
data class Contact(
    val id: String,
    val firstName: String,
    val lastName: String = "",
    val phone: String = "",
    val avatarUrl: String? = null,
    val isOnline: Boolean = false,
    /** Когда был в сети (мс), 0 — неизвестно. */
    val lastSeenMs: Long = 0,
    /** Опция `BOT`. */
    val isBot: Boolean = false,
    /** Опция `OFFICIAL`. */
    val isOfficial: Boolean = false,
    /** Опция `SERVICE_ACCOUNT`. */
    val isServiceAccount: Boolean = false,
    /** Имя по правилу ядра (книга, своё имя контакта, имя профиля); `null` — из имени и фамилии. */
    val label: String? = null,
) {
    val displayName: String
        get() {
            label?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            val name = listOf(firstName.trim(), lastName.trim()).filter { it.isNotEmpty() }.joinToString(" ")
            if (name.isNotEmpty()) return name
            // Дальше — как у ядра (ContactNames): номер «+79131234567» (не приводится — как есть), «Участник».
            PhoneNumbers.normalize(phone)?.let { return it }
            phone.trim().takeIf { it.isNotEmpty() }?.let { return it }
            return ContactNames.FALLBACK
        }
}
