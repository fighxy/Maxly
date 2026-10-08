package app.orbitle.data

import com.max.core.api.Chat as CoreChat
import com.max.core.api.ChatMember
import com.max.core.api.ChatPermission
import com.max.core.api.GroupSettings
import com.max.core.api.MaxUser
import com.max.core.protocol.Opcode
import com.max.shared.MaxClient

/** [ChatAdminRepository] через `ChatsApi` ядра. */
class CoreChatAdminRepository(private val client: MaxClient) : ChatAdminRepository {
    override suspend fun snapshot(chatId: String): ChatAdminSnapshot {
        val chat = chat(chatId)
        return snapshotOf(chat)
    }

    override suspend fun saveCard(chatId: String, title: String, description: String) {
        val name = title.trim()
        if (name.isEmpty()) throw app.orbitle.domain.OrbitleError.Rejected("Название не может быть пустым")
        store(MaxCoreGateway.call {
            client.api.chats.updateProfile(id(chatId), title = name, description = description.trim())
        })
    }

    override suspend fun setPhoto(chatId: String, jpeg: ByteArray) {
        if (jpeg.isEmpty()) throw app.orbitle.domain.OrbitleError.Rejected("Файл пустой")
        val token = MaxCoreGateway.call { client.media.uploadPhoto(jpeg, "chat.jpg").photoToken }
        store(MaxCoreGateway.call { client.api.chats.updateProfile(id(chatId), photoToken = token) })
    }

    override suspend fun members(chatId: String): List<ChatPerson> {
        val numeric = id(chatId)
        // Список чатов часто без `admins`. Карточка нужна до ролей.
        val stored = MaxCoreGateway.call { client.api.chats.getChat(numeric) }.also { store(it) }
        val admins = adminIds(stored)
        val owner = stored.owner
        val all = ArrayList<ChatMember>()
        var marker = 0L
        var pages = 0
        while (pages < MEMBER_PAGES) {
            pages += 1
            val page = MaxCoreGateway.call { client.api.chats.getChatMembers(numeric, marker, MEMBER_PAGE) }
            if (page.members.isEmpty()) break
            all += page.members
            val next = page.marker
            // Без `marker` в ответе — последняя страница.
            if (next == null || next == 0L || next == marker || page.members.size < MEMBER_PAGE) break
            marker = next
        }
        return all.mapNotNull { person(it, owner, admins) }
    }

    override suspend fun addMembers(chatId: String, userIds: List<String>) {
        val ids = userIds.mapNotNull { it.toLongOrNull() }
        if (ids.isEmpty()) return
        store(MaxCoreGateway.call { client.api.chats.addMembers(id(chatId), ids) })
    }

    override suspend fun removeMember(chatId: String, userId: String) {
        store(MaxCoreGateway.call { client.api.chats.removeMembers(id(chatId), listOf(id(userId))) })
    }

    override suspend fun setAdmin(chatId: String, userId: String, admin: Boolean) {
        val chat = id(chatId)
        val user = id(userId)
        if (admin) {
            MaxCoreGateway.call { client.api.chats.addAdmin(chat, user, ChatPermission.entries.toSet()) }
        } else {
            // Снятие админа ядро отдельным методом не отдаёт: тот же пакет 77, operation remove.
            MaxCoreGateway.call {
                client.session.request(
                    Opcode.CHAT_MEMBERS_UPDATE,
                    linkedMapOf(
                        "chatId" to chat,
                        "userIds" to listOf(user),
                        "type" to "ADMIN",
                        "operation" to "remove",
                    ),
                )
            }
        }
        // Роль лежит в `admins` карточки, не в строке участника. Берём свежую карточку до перечитывания списка.
        store(MaxCoreGateway.call { client.api.chats.getChat(chat) })
    }

    override suspend fun revokeInviteLink(chatId: String): String? {
        val chat = MaxCoreGateway.call { client.api.chats.revokeInviteLink(id(chatId)) }
        client.store.putChats(listOf(chat))
        return linkOf(chat.raw)
    }

    override suspend fun joinRequests(chatId: String): List<ChatPerson> {
        val owner = ownerId(chatId)
        val list = MaxCoreGateway.call { client.api.chats.getJoinRequests(id(chatId)) }
        return list.mapNotNull { person(it, owner, emptySet()) }
    }

    override suspend fun decideJoinRequest(chatId: String, userId: String, accept: Boolean) {
        val chat = id(chatId)
        val user = listOf(id(userId))
        store(MaxCoreGateway.call {
            if (accept) client.api.chats.confirmJoinRequests(chat, user) else client.api.chats.declineJoinRequests(chat, user)
        })
    }

    override suspend fun setOption(chatId: String, option: GroupOption, enabled: Boolean) {
        val settings = when (option) {
            GroupOption.ONLY_OWNER_RENAMES -> GroupSettings(onlyOwnerCanChangeIconTitle = enabled)
            GroupOption.ALL_CAN_PIN -> GroupSettings(allCanPinMessage = enabled)
            GroupOption.ONLY_ADMIN_ADDS -> GroupSettings(onlyAdminCanAddMember = enabled)
            GroupOption.ONLY_ADMIN_CALLS -> GroupSettings(onlyAdminCanCall = enabled)
            GroupOption.MEMBERS_SEE_LINK -> GroupSettings(membersCanSeePrivateLink = enabled)
        }
        store(MaxCoreGateway.call { client.api.chats.updateSettings(id(chatId), settings) })
    }

    override suspend fun setComments(chatId: String, enabled: Boolean) {
        store(MaxCoreGateway.call { client.api.chats.setChannelComments(id(chatId), enabled) })
    }

    override suspend fun blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String) {
        store(MaxCoreGateway.call {
            client.api.chats.blockCommentAuthors(id(chatId), id(postId), listOf(id(userId)), id(messageId))
        })
    }

    private fun id(value: String) = value.toLong()

    private suspend fun chat(chatId: String): CoreChat {
        val numeric = id(chatId)
        return client.store.state.value.chats[numeric]
            ?: MaxCoreGateway.call { client.api.chats.getChat(numeric) }.also { client.store.putChats(listOf(it)) }
    }

    private suspend fun ownerId(chatId: String) = chat(chatId).owner

    private fun store(chat: CoreChat?) {
        if (chat != null) client.store.putChats(listOf(chat))
    }

    private fun person(member: ChatMember, ownerId: Long?, admins: Set<Long>): ChatPerson? {
        val user = MaxUser.from(member.contact) ?: return null
        val role = when {
            ownerId != null && user.id == ownerId -> ChatPerson.Role.OWNER
            user.id in admins -> ChatPerson.Role.ADMIN
            else -> ChatPerson.Role.MEMBER
        }
        val presence = PresenceTime.freshest(client.store.state.value.presence[user.id], PresenceTime.from(member.presence))
        return ChatPerson(
            user.id.toString(),
            user.displayName?.trim().orEmpty().ifEmpty { "Участник" },
            role,
            isOnline = PresenceTime.isOnline(presence),
            lastSeenMs = PresenceTime.ms(presence?.seen),
        )
    }

    /** Id из `admins` и ключей `adminParticipants` карточки чата. */
    private fun adminIds(chat: CoreChat): Set<Long> {
        val ids = LinkedHashSet<Long>()
        fun add(value: Any?) {
            when (value) {
                is Number -> ids += value.toLong()
                is String -> value.toLongOrNull()?.let { ids += it }
                is Map<*, *> -> add(value["id"] ?: value["userId"])
            }
        }
        (chat.raw["admins"] as? Collection<*>)?.forEach(::add)
        when (val participants = chat.raw["adminParticipants"]) {
            is Map<*, *> -> participants.keys.forEach(::add)
            is Collection<*> -> participants.forEach(::add)
        }
        return ids
    }

    companion object {
        fun snapshotOf(chat: CoreChat): ChatAdminSnapshot {
            val options = chat.raw["options"] as? Map<*, *>
            fun flag(key: String) = options?.get(key) == true
            val comments = options?.get("COMMENTS") as? Boolean
            return ChatAdminSnapshot(
                title = chat.title.orEmpty(),
                description = (chat.raw["description"] as? String).orEmpty(),
                link = linkOf(chat.raw),
                ownerId = chat.owner?.toString(),
                commentsEnabled = comments,
                onlyOwnerCanChangeIconTitle = flag("ONLY_OWNER_CAN_CHANGE_ICON_TITLE"),
                allCanPinMessage = flag("ALL_CAN_PIN_MESSAGE"),
                onlyAdminCanAddMember = flag("ONLY_ADMIN_CAN_ADD_MEMBER"),
                onlyAdminCanCall = flag("ONLY_ADMIN_CAN_CALL"),
                membersCanSeePrivateLink = flag("MEMBERS_CAN_SEE_PRIVATE_LINK"),
            )
        }

        private const val MEMBER_PAGE = 50
        private const val MEMBER_PAGES = 40

        fun linkOf(raw: Map<*, *>): String? {
            for (key in listOf("link", "inviteLink", "privateLink", "baseLink")) {
                val value = raw[key] as? String
                if (!value.isNullOrBlank()) return value
            }
            return null
        }
    }
}
