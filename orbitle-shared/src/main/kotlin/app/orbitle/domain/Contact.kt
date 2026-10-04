package app.orbitle.domain

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
) {
    val displayName: String
        get() {
            val name = listOf(firstName.trim(), lastName.trim()).filter { it.isNotEmpty() }.joinToString(" ")
            if (name.isNotEmpty()) return name
            val digits = phone.filter { it.isDigit() }
            if (digits.isNotEmpty()) return "+$digits"
            return "Без имени"
        }
}
