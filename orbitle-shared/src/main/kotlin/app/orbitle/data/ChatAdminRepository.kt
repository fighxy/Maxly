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

/**
 * Человек в списке участников, заявок или контактов. [alias] — подпись админа; [mentionName] — имя
 * для упоминаний (ник без «@»), если оно известно (ядро его пока не отдаёт).
 */
data class ChatPerson(
    val id: String,
    val name: String,
    val role: Role = Role.MEMBER,
    val alias: String? = null,
    val mentionName: String? = null,
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
interface ChatAdminRepository : ChatMembersSource {
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

    /** Без постраничного списка — весь [members] одной страницей. */
    override suspend fun memberPage(chatId: String, marker: Long?): MemberPage =
        if (marker == null) MemberPage(members(chatId), null) else MemberPage(emptyList(), null)

    /** Без поиска на сервере — по именам из [members]. */
    override suspend fun searchMembers(chatId: String, query: String): List<ChatPerson> =
        MemberSearch.filter(members(chatId), query)
}

/**
 * Поиск среди загруженных участников (общий с iOS, `test-fixtures/members/search`): подстрока
 * имени или имени для упоминаний без учёта регистра, «ё» = «е», пробелы запроса по краям не
 * важны, пустой запрос — все. Запрос с «@» ищет только по [ChatPerson.mentionName], «@» без
 * текста — все. Порядок сохраняется.
 */
object MemberSearch {
    fun filter(people: List<ChatPerson>, query: String): List<ChatPerson> {
        val needle = fold(query.trim())
        if (needle.isEmpty()) return people
        val byMention = needle.startsWith("@")
        val mention = needle.removePrefix("@")
        if (byMention && mention.isEmpty()) return people
        return people.filter { person ->
            (!byMention && fold(person.name).contains(needle)) ||
                person.mentionName?.let { fold(it).contains(mention) } == true
        }
    }

    private fun fold(text: String): String = text.lowercase().replace('ё', 'е')
}
