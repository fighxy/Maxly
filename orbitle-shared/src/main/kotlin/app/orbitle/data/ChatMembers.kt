package app.orbitle.data

import com.max.core.api.ChatMemberEntry
import com.max.core.api.ChatMemberRole
import com.max.core.api.PresenceInfo
import com.max.shared.MaxClient

/** Страница участников и `marker` следующей; `null` — страница последняя. */
data class MemberPage(val members: List<ChatPerson>, val next: Long?)

/** Участники группы или канала постранично и поиск среди них. */
interface ChatMembersSource {
    /** Страница с [marker]; `null` — первая. */
    suspend fun memberPage(chatId: String, marker: Long? = null): MemberPage

    suspend fun searchMembers(chatId: String, query: String): List<ChatPerson>
}

/**
 * Участники через ядро: [MaxClient.loadChatMembers] по `marker` и [MaxClient.searchChatMembers].
 * Роли — из карточки чата в сторе ([com.max.core.api.ChatRoles]), имена — [MaxClient.displayLabel].
 */
class CoreChatMembers(private val client: MaxClient, private val pageSize: Int = PAGE) : ChatMembersSource {
    override suspend fun memberPage(chatId: String, marker: Long?): MemberPage {
        val id = chatId.toLongOrNull() ?: return MemberPage(emptyList(), null)
        val page = MaxCoreGateway.call { client.loadChatMembers(id, marker ?: 0L, pageSize) }
        return MemberPage(page.members.mapNotNull { person(it, client::displayLabel, ::presence) }, page.nextMarker)
    }

    override suspend fun searchMembers(chatId: String, query: String): List<ChatPerson> {
        val id = chatId.toLongOrNull() ?: return emptyList()
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        return MaxCoreGateway.call { client.searchChatMembers(id, term) }.mapNotNull { person(it, client::displayLabel, ::presence) }
    }

    /** Присутствие из стора (пуши), если оно уже есть. */
    private fun presence(userId: Long): PresenceInfo? = client.store.state.value.presence[userId]

    companion object {
        /**
         * Участник ядра для экрана: роль и подпись админа — из карточки чата, имя — [name],
         * присутствие — свежее из [stored] (стор) и самой страницы.
         */
        fun person(entry: ChatMemberEntry, name: (Long) -> String, stored: (Long) -> PresenceInfo? = { null }): ChatPerson? {
            val id = entry.userId ?: entry.user?.id ?: return null
            val role = when (entry.role) {
                ChatMemberRole.OWNER -> ChatPerson.Role.OWNER
                ChatMemberRole.ADMIN -> ChatPerson.Role.ADMIN
                ChatMemberRole.MEMBER -> ChatPerson.Role.MEMBER
            }
            val presence = PresenceTime.freshest(stored(id), PresenceTime.from(entry.member.presence))
            return ChatPerson(
                id.toString(),
                name(id),
                role,
                alias = entry.admin?.alias?.takeIf { role == ChatPerson.Role.ADMIN },
                mentionName = entry.user?.mentionName,
                isOnline = PresenceTime.isOnline(presence),
                lastSeenMs = PresenceTime.ms(presence?.seen),
            )
        }

        const val PAGE = 50
        const val PAGES = 40
    }
}
