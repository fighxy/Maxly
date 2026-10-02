package app.orbitle.domain

/** Свой профиль для шапки настроек. */
data class Account(
    val id: String,
    val firstName: String,
    val lastName: String,
    /** Номер в виде `+79991234567`. */
    val phone: String?,
    val avatarUrl: String?,
    val description: String? = null,
    val link: String? = null,
) {
    val displayName: String get() = listOf(firstName, lastName).filter { it.isNotBlank() }.joinToString(" ")
}
