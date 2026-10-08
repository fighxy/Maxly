package app.orbitle.data

/** Снимок группы или канала для экрана управления. Флаги прав — как их прислал сервер. */
data class ChatAdminSnapshot(
    val title: String,
    val description: String,
    val link: String?,
    val ownerId: String?,
    /** `null` — не канал или сервер не прислал опцию. */
    val commentsEnabled: Boolean?,
    val onlyOwnerCanChangeIconTitle: Boolean,
    val allCanPinMessage: Boolean,
    val onlyAdminCanAddMember: Boolean,
    val onlyAdminCanCall: Boolean,
    val membersCanSeePrivateLink: Boolean,
)

/** Человек в списке участников, заявок или контактов. */
data class ChatPerson(
    val id: String,
    val name: String,
    val role: Role = Role.MEMBER,
    /** Присутствие, если оно уже известно (стор или сама страница участников); `0` — неизвестно. */
    val isOnline: Boolean = false,
    val lastSeenMs: Long = 0,
) {
    enum class Role { OWNER, ADMIN, MEMBER }
}

/** Какой флаг группы меняется одним запросом. */
enum class GroupOption {
    ONLY_OWNER_RENAMES,
    ALL_CAN_PIN,
    ONLY_ADMIN_ADDS,
    ONLY_ADMIN_CALLS,
    MEMBERS_SEE_LINK,
}

/**
 * Управление группой и каналом: карточка, участники, админы, ссылка, заявки, права, комментарии.
 * Передача владения и набор реакций чата в API ядра не описаны и сюда не входят.
 */
interface ChatAdminRepository {
    suspend fun snapshot(chatId: String): ChatAdminSnapshot
    suspend fun saveCard(chatId: String, title: String, description: String)
    suspend fun setPhoto(chatId: String, jpeg: ByteArray)
    suspend fun members(chatId: String): List<ChatPerson>
    suspend fun addMembers(chatId: String, userIds: List<String>)
    suspend fun removeMember(chatId: String, userId: String)
    suspend fun setAdmin(chatId: String, userId: String, admin: Boolean)
    suspend fun revokeInviteLink(chatId: String): String?
    suspend fun joinRequests(chatId: String): List<ChatPerson>
    suspend fun decideJoinRequest(chatId: String, userId: String, accept: Boolean)
    suspend fun setOption(chatId: String, option: GroupOption, enabled: Boolean)
    suspend fun setComments(chatId: String, enabled: Boolean)
    /** Заблокировать автора комментария под постом канала. */
    suspend fun blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String)
}
