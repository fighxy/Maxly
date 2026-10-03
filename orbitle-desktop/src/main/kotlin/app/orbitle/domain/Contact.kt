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
) {
    val displayName: String
        get() = listOf(firstName.trim(), lastName.trim()).filter { it.isNotEmpty() }.joinToString(" ").ifEmpty { phone.ifEmpty { "Без имени" } }
}
