package app.maxly.domain

/** Папка списка чатов: серверная или локальный фильтр по типу. */
data class ChatFolder(val id: String, val title: String, val filter: Filter) {

    /** Какие чаты попадают в папку. */
    sealed interface Filter {
        /** Все чаты, кроме архива. */
        data object All : Filter
        data object PrivateChats : Filter
        data object Groups : Filter
        data object Channels : Filter
        data object Bots : Filter
        data object Unread : Filter
        /** Серверная папка: перечисленные чаты и чаты под фильтры сервера. */
        data class Rules(val rules: ChatFolderRules) : Filter
    }

    /** Входит ли чат в папку. Архив в папки не попадает. */
    fun contains(chat: Chat): Boolean {
        if (chat.isArchived) return false
        return when (filter) {
            Filter.All -> true
            Filter.PrivateChats -> chat.type == ChatType.PRIVATE && !chat.isBot && !chat.isSavedMessages
            Filter.Groups -> chat.type == ChatType.GROUP
            Filter.Channels -> chat.type == ChatType.CHANNEL
            Filter.Bots -> chat.isBot
            Filter.Unread -> chat.isUnread
            is Filter.Rules -> filter.rules.matches(chat)
        }
    }

    companion object {
        const val ALL_ID = "all"
        val all = ChatFolder(ALL_ID, "Все", Filter.All)

        /** Фильтры, которые клиент строит сам, когда у пользователя нет серверных папок. */
        val localFilters = listOf(
            ChatFolder("local.private", "Личные", Filter.PrivateChats),
            ChatFolder("local.groups", "Группы", Filter.Groups),
            ChatFolder("local.channels", "Каналы", Filter.Channels),
            ChatFolder("local.bots", "Боты", Filter.Bots),
            ChatFolder("local.unread", "Непрочитанные", Filter.Unread),
        )
    }
}

/** Папка сервера, как её прислало ядро. */
data class ServerFolder(
    val id: String,
    val title: String,
    val chatIds: List<String> = emptyList(),
    /** Фильтры сервера текстом: коды (`"4"`) или имена (`"DIALOG"`). */
    val filters: List<String> = emptyList(),
    /** Системная папка «Все»: не редактируется и стоит первой. */
    val isAllChats: Boolean = false,
) {
    val chatFolder: ChatFolder
        get() = ChatFolder(id, title, ChatFolder.Filter.Rules(ChatFolderRules(chatIds.toSet(), filters)))
}

/**
 * Правила серверной папки: явный список чатов и фильтры.
 *
 * Коды фильтров как у сервера MAX: 0 непрочитанные, 1 прочитанные, 2 каналы, 3 группы,
 * 4 диалоги, 5 владелец, 6 админ, 7 без звука, 8 контакты, 9 не контакты, 10 боты,
 * 11 со звуком, 12 отмеченные непрочитанными, 13 организации. Сервер может прислать и имена
 * (`CHANNEL`, `BOT`…). Типы объединяются по «или», состояния сужают по «и». Роли, контакты
 * и организации клиент не знает: «контакты» и «не контакты» считаются диалогами, роли
 * и организации не сужают.
 */
class ChatFolderRules(val chatIds: Set<String> = emptySet(), filters: List<String> = emptyList()) {

    enum class Code(val value: Int) {
        UNREAD(0), READ(1), CHANNEL(2), GROUP(3), DIALOG(4), OWNER(5), ADMIN(6), MUTED(7),
        CONTACT(8), NOT_CONTACT(9), BOT(10), NOT_MUTED(11), MARKED_UNREAD(12), ORGANIZATION(13);

        val isType: Boolean
            get() = this in setOf(CHANNEL, GROUP, DIALOG, CONTACT, NOT_CONTACT, BOT, ORGANIZATION)

        val isState: Boolean
            get() = this in setOf(UNREAD, READ, MUTED, NOT_MUTED, MARKED_UNREAD)

        companion object {
            private val names = mapOf(
                "UNREAD" to UNREAD, "READ" to READ, "CHANNEL" to CHANNEL, "CHAT" to GROUP, "DIALOG" to DIALOG,
                "OWNER" to OWNER, "ADMIN" to ADMIN, "MUTED" to MUTED, "CONTACT" to CONTACT, "NOT_CONTACT" to NOT_CONTACT,
                "BOT" to BOT, "NOT_MUTED" to NOT_MUTED, "MARKED_UNREAD" to MARKED_UNREAD, "ORG" to ORGANIZATION,
            )

            /** Код из текста сервера: число или имя. `null` для незнакомого. */
            fun fromText(text: String): Code? {
                val value = text.trim()
                value.toIntOrNull()?.let { number -> return entries.firstOrNull { it.value == number } }
                return names[value.uppercase()]
            }
        }
    }

    val codes: Set<Code> = filters.mapNotNull(Code::fromText).toSet()

    fun matches(chat: Chat): Boolean {
        if (chat.id in chatIds) return true
        val types = codes.filter { it.isType }
        val states = codes.filter { it.isState }
        if (types.isEmpty() && states.isEmpty()) return false
        if (types.isNotEmpty() && types.none { isOfType(chat, it) }) return false
        return states.all { isInState(chat, it) }
    }

    private fun isOfType(chat: Chat, code: Code): Boolean = when (code) {
        Code.CHANNEL -> chat.type == ChatType.CHANNEL
        Code.GROUP -> chat.type == ChatType.GROUP
        Code.DIALOG, Code.CONTACT, Code.NOT_CONTACT -> chat.type == ChatType.PRIVATE && !chat.isBot && !chat.isSavedMessages
        Code.BOT -> chat.isBot
        else -> false
    }

    private fun isInState(chat: Chat, code: Code): Boolean = when (code) {
        Code.UNREAD, Code.MARKED_UNREAD -> chat.isUnread
        Code.READ -> !chat.isUnread
        Code.MUTED -> chat.isMuted
        Code.NOT_MUTED -> !chat.isMuted
        else -> true
    }

    override fun equals(other: Any?): Boolean = other is ChatFolderRules && other.chatIds == chatIds && other.codes == codes
    override fun hashCode(): Int = chatIds.hashCode() * 31 + codes.hashCode()
}
