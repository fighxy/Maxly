package app.maxly.domain

/** Публичный чат или канал, найденный на сервере; в списке пользователя его может не быть. */
data class ChatSearchResult(
    val id: String,
    val title: String,
    /** `@ссылка` или последнее сообщение; `null`, если нечего показать. */
    val subtitle: String?,
    val type: ChatType,
    val avatarUrl: String?,
)
