package app.maxly.domain

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
    /** Есть фото профиля: его можно удалить. */
    val hasPhoto: Boolean = avatarUrl != null,
    /**
     * Оригинал своего фото для просмотра и сохранения (`avatarFullUrl` ядра, без `fn`); `null` —
     * фото нет. [avatarUrl] — только квадрат для шапки.
     */
    val avatarFullUrl: String? = null,
    /** Запасные размеры своего фото от большего к меньшему (`avatarViewerUrls` ядра). */
    val avatarViewerUrls: List<String> = emptyList(),
) {
    val displayName: String get() = listOf(firstName, lastName).filter { it.isNotBlank() }.joinToString(" ")
}
