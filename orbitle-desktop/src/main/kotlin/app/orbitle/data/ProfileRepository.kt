package app.orbitle.data

import app.orbitle.domain.ChatProfile
import app.orbitle.domain.Message
import app.orbitle.domain.SharedMediaTab
import com.max.shared.MaxClient
import com.max.core.api.Chat as CoreChat

/** Профиль чата и его общие медиа. */
interface ProfileRepository {
    /** То, что уже есть на устройстве: шапка видна сразу. */
    fun cached(chatId: String): ChatProfile?

    /** Свежая карточка с сервера. */
    suspend fun profile(chatId: String): ChatProfile

    /**
     * Страница сообщений вкладки [tab] старше [beforeMessageId] (включительно), новые первыми.
     * Пустой список — дальше ничего нет.
     */
    suspend fun sharedPage(chatId: String, tab: SharedMediaTab, beforeMessageId: String): List<Message>
}

class CoreProfileRepository(private val client: MaxClient) : ProfileRepository {

    override fun cached(chatId: String): ChatProfile? {
        val id = chatId.toLongOrNull() ?: return null
        val state = client.store.state.value
        val chat = state.chats[id]
        if (chat != null && chat.type != "DIALOG") return chatProfile(chat)
        val me = state.me
        val peer = chat?.let { ChatMapping.dialogPeer(it, me) } ?: me?.let { id xor it }
        if (peer == null || peer == me || peer == 0L) return ChatProfile(ChatProfile.Kind.SAVED, chatId)
        val user = state.users[peer] ?: return null
        return userProfile(chatId, user, null)
    }

    override suspend fun profile(chatId: String): ChatProfile {
        val id = chatId.toLong()
        val state = client.store.state.value
        val stored = state.chats[id]
        val chat = if (stored == null || stored.type != "DIALOG") {
            runCatching { MaxCoreGateway.call { client.api.chats.getChat(id) } }.getOrNull() ?: stored
        } else {
            stored
        }
        if (chat != null && chat.type != "DIALOG") return chatProfile(chat)
        val me = client.store.state.value.me
        val peer = chat?.let { ChatMapping.dialogPeer(it, me) } ?: me?.let { id xor it }
        if (peer == null || peer == me || peer == 0L) return ChatProfile(ChatProfile.Kind.SAVED, chatId)
        val user = MaxCoreGateway.call { client.loadUsers(listOf(peer)) }.firstOrNull { it.id == peer }
            ?: client.store.state.value.users[peer]
            ?: throw app.orbitle.domain.OrbitleError.Rejected("Пользователь не найден")
        val bot = if ("BOT" !in user.options) null else runCatching { MaxCoreGateway.call { client.api.bots.getBotInfo(peer) } }.getOrNull()
        return userProfile(chatId, bot?.contact ?: user, bot?.commands?.map { ChatProfile.BotCommand(it.name, it.description) }, displayFrom = user)
    }

    private fun userProfile(
        chatId: String,
        card: com.max.core.api.MaxUser,
        commands: List<ChatProfile.BotCommand>?,
        displayFrom: com.max.core.api.MaxUser = card,
    ): ChatProfile {
        val presence = client.store.state.value.presence[displayFrom.id]
        val bot = "BOT" in displayFrom.options
        return ChatProfile(
            kind = if (bot) ChatProfile.Kind.BOT else ChatProfile.Kind.USER,
            chatId = chatId,
            title = displayFrom.displayName.orEmpty(),
            avatarUrl = displayFrom.baseUrl?.takeIf { it.isNotEmpty() },
            peerId = displayFrom.id.toString(),
            description = card.description?.trim()?.takeIf { it.isNotEmpty() },
            link = card.link?.takeIf { it.isNotEmpty() }?.let(::absoluteLink),
            phone = displayFrom.phone?.takeIf { it > 0 }?.toString(),
            isOnline = presence?.status == 1,
            lastSeenMs = presence?.seen?.let { if (it < 100_000_000_000L) it * 1000 else it } ?: 0L,
            isOfficial = "OFFICIAL" in displayFrom.options,
            commands = commands.orEmpty(),
        )
    }

    private fun chatProfile(chat: CoreChat): ChatProfile {
        val options = chat.raw["options"] as? Map<*, *>
        return ChatProfile(
            kind = if (chat.type == "CHANNEL") ChatProfile.Kind.CHANNEL else ChatProfile.Kind.GROUP,
            chatId = chat.id.toString(),
            title = chat.title.orEmpty(),
            avatarUrl = (chat.raw["baseIconUrl"] as? String)?.takeIf { it.isNotEmpty() },
            description = (chat.raw["description"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
            link = (chat.raw["link"] as? String)?.takeIf { it.isNotEmpty() }?.let(::absoluteLink),
            participants = chat.participantsCount.takeIf { it > 0 },
            isOfficial = options?.get("OFFICIAL") == true,
            isPublic = chat.raw["access"] == "PUBLIC",
        )
    }

    override suspend fun sharedPage(chatId: String, tab: SharedMediaTab, beforeMessageId: String): List<Message> {
        val id = chatId.toLong()
        val page = MaxCoreGateway.call { client.api.messages.getChatMedia(id, beforeMessageId.toLong(), tab.attachTypes, forward = 0, backward = PAGE) }
        val state = client.store.state.value
        return page.messages.map { MessageMapping.message(it, id, state) }.sortedByDescending { it.timeMs }
    }

    private companion object {
        const val PAGE = 40

        /** `name` или `max.ru/name` → полный адрес. */
        fun absoluteLink(link: String): String = when {
            link.startsWith("http://") || link.startsWith("https://") -> link
            link.contains('/') -> "https://$link"
            else -> "https://max.ru/$link"
        }
    }
}
