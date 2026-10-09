package app.maxly.data

import app.maxly.domain.Chat
import app.maxly.domain.ChatSearchResult
import app.maxly.domain.ChatType
import app.maxly.domain.FoundMessage
import com.maxly.core.api.Chat as CoreChat
import com.maxly.core.api.MaxMessage
import com.maxly.core.api.PublicSearchHit
import com.maxly.core.events.MaxEvent
import com.maxly.core.protocol.Opcode
import com.maxly.core.state.MaxState
import kotlinx.coroutines.CancellationException
import app.maxly.domain.ServerFolder
import com.maxly.shared.MaxClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** [ChatRepository] над стором `MaxClient`. */
class CoreChatRepository(
    private val client: MaxClient,
    private val clock: () -> Long = System::currentTimeMillis,
) : ChatRepository {

    /** Снимок уже пришёл: до него список показывает загрузку, а не «Нет чатов». */
    private val loaded = MutableStateFlow(false)
    private val refreshLock = Mutex()
    /** Закрепление и перестановка по очереди: каждый запрос строится от списка, принятого сервером. */
    private val pinLock = Mutex()
    private var usersRequested = mutableSetOf<Long>()
    private val mutes = ChatMutes.of(client)

    override val chats: Flow<List<Chat>?> =
        ChatMutes.chatList(client.store.state, client.accountConfig, loaded, mutes, clock, ChatMutes.configPushes(client))

    override val folders: Flow<List<ServerFolder>> = client.store.state
        .map { it.chatFolders }
        .distinctUntilChanged()
        .map { folders -> ChatMapping.folders(folders).filterNot { it.isAllChats } }

    private val ticks: Flow<Long> = flow {
        while (true) {
            emit(clock())
            delay(TYPING_TICK_MS)
        }
    }

    private val typists = TypingTracker()

    override val typing: Flow<Map<String, List<app.maxly.domain.Typist>>> = combine(client.store.state, ticks) { state, now ->
        state.typing.keys.mapNotNull { chatId ->
            val list = typists.typists(state, chatId, now) { state.displayName(it)?.takeIf(String::isNotBlank) }
            if (list.isEmpty()) null else chatId.toString() to list
        }.toMap()
    }.distinctUntilChanged()

    override suspend fun refresh() {
        if (refreshLock.isLocked) return
        refreshLock.withLock {
            MaxCoreGateway.read {
                if (client.store.state.value.chats.isEmpty()) client.loadAllChats() else client.loadChats()
            }
            runCatching { MaxCoreGateway.call { client.loadFolders() } }
            loaded.value = true
            resolveUsers()
        }
    }

    /** Собеседники и авторы последних сообщений, которых ещё нет в сторе, порциями по 100. */
    private suspend fun resolveUsers() {
        val state = client.store.state.value
        val wanted = buildSet {
            for (chat in state.chats.values) {
                ChatMapping.dialogPeer(chat, state.me)?.let(::add)
                chat.lastMessage?.sender?.let(::add)
            }
        }.filter { it !in state.users && it !in usersRequested }
        if (wanted.isEmpty()) return
        usersRequested.addAll(wanted)
        for (chunk in wanted.chunked(100)) {
            runCatching { MaxCoreGateway.call { client.loadUsers(chunk) } }
        }
    }

    override suspend fun setPinned(chatId: String, pinned: Boolean) {
        val id = chatId.toLongOrNull() ?: return
        pinLock.withLock {
            val current = client.store.state.value.pinnedChatIds.orEmpty()
            val next = if (pinned) listOf(id) + current.filter { it != id } else current.filter { it != id }
            MaxCoreGateway.call { client.setPinnedChats(next) }
        }
    }

    override suspend fun reorderPinned(chatIds: List<String>) {
        pinLock.withLock {
            val current = client.store.state.value.pinnedChatIds.orEmpty()
            val next = pinOrder(current, chatIds)
            if (next != current) MaxCoreGateway.call { client.setPinnedChats(next) }
        }
    }

    override suspend fun setMuted(chatId: String, muted: Boolean) {
        val id = chatId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.setChatMuted(id, muted) }
    }

    override suspend fun searchPublic(query: String): List<ChatSearchResult> {
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        val hits = MaxCoreGateway.call { client.api.search.searchPublic(term, 0, SEARCH_PAGE_SIZE) }
        return hits.mapNotNull(::searchResultOf)
    }

    override suspend fun searchMessages(query: String): List<FoundMessage> {
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        // Без ответа сервера остаются совпадения среди загруженных сообщений.
        val hits = try {
            MaxCoreGateway.call { client.api.search.searchMessages(term, MESSAGE_SEARCH_COUNT) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            emptyList()
        }
        return foundMessages(term, hits.map { it.chatId to it.message }, client.store.state.value)
    }

    override suspend fun createGroup(title: String, memberIds: List<String>): String? {
        val ids = memberIds.mapNotNull { it.toLongOrNull() }
        val created = MaxCoreGateway.call { client.api.chats.createGroup(title, ids, notify = true) } ?: return null
        client.store.putChats(listOf(created.chat))
        return created.chat.id.toString()
    }

    override suspend fun createChannel(title: String): String? {
        val chat = MaxCoreGateway.call {
            val payload = channelCreatePayload(client.api.messages.nextCid(), title)
            val map = client.session.request(Opcode.MSG_SEND, payload).payload as? Map<*, *> ?: return@call null
            CoreChat.from(map["chat"])
        } ?: return null
        client.store.putChats(listOf(chat))
        return chat.id.toString()
    }

    override suspend fun prepareDialog(chatId: String, peerId: String, title: String) {
        val id = chatId.toLongOrNull() ?: return
        val peer = peerId.toLongOrNull() ?: return
        val state = client.store.state.value
        if (id in state.chats) return
        val me = state.me ?: client.userId.value
        client.store.putChats(listOf(dialogPlaceholder(id, me, peer, title)))
    }

    override suspend fun markAsRead(chatId: String) {
        val id = chatId.toLongOrNull() ?: return
        val state = client.store.state.value
        val last = state.chats[id]?.lastMessage?.id ?: state.messagesOf(id).maxByOrNull { it.time }?.id ?: return
        ReadMarks.send(client, id, last)
    }

    private val people = CoreChatMembers(client)

    override suspend fun members(chatId: String): List<ChatMemberRow> =
        people.memberPage(chatId).members.map { ChatMemberRow(it.id, it.name, mentionName = it.mentionName, isOnline = it.isOnline, lastSeenMs = it.lastSeenMs) }

    override suspend fun memberPage(chatId: String, marker: Long?): MemberPage = people.memberPage(chatId, marker)

    override suspend fun searchMembers(chatId: String, query: String): List<ChatPerson> = people.searchMembers(chatId, query)

    override suspend fun commonChats(userId: String): List<SharedChat> {
        val id = userId.toLongOrNull() ?: return emptyList()
        val packet = MaxCoreGateway.call {
            client.session.request(Opcode.CHAT_SEARCH_COMMON_PARTICIPANTS, LockPayloads.commonChats(id))
        }
        return LockPayloads.sharedChats(packet.payload)
    }

    override suspend fun complaintReasons(): Map<Int, List<ComplaintChoice>> {
        val packet = MaxCoreGateway.call {
            client.session.request(Opcode.COMPLAIN_REASONS_GET, LockPayloads.complaintReasons())
        }
        return LockPayloads.complaintChoices(packet.payload)
    }

    override suspend fun complain(reasonId: Int, typeId: Int, ids: List<String>, parentId: String?): Boolean {
        val numeric = ids.mapNotNull { it.toLongOrNull() }
        if (numeric.isEmpty()) return false
        val parent = parentId?.toLongOrNull()
        val packet = MaxCoreGateway.call {
            client.session.request(Opcode.COMPLAIN, LockPayloads.complaint(reasonId, typeId, numeric, parent))
        }
        return (packet.payload as? Map<*, *>)?.get("success") == true
    }

    override suspend fun signalCall(calleeId: String, isVideo: Boolean): SignaledCall? {
        val id = calleeId.toLongOrNull() ?: return null
        val conversationId = java.util.UUID.randomUUID().toString()
        val packet = MaxCoreGateway.call {
            client.session.request(
                Opcode.VIDEO_CHAT_START_ACTIVE,
                LockPayloads.initiateCall(conversationId, id, client.device.deviceId, isVideo),
            )
        }
        val map = packet.payload as? Map<*, *> ?: return null
        val endpoint = LockPayloads.endpointOf(map["internalCallerParams"] as? String) ?: return null
        val conversation = (map["conversationId"] as? String)?.takeIf { it.isNotEmpty() } ?: conversationId
        return SignaledCall(conversation, endpoint)
    }

    override suspend fun joinByLink(link: String): String? {
        val trimmed = link.trim()
        if (trimmed.isEmpty()) return null
        val chat = MaxCoreGateway.call { client.api.chats.join(trimmed) }
        client.store.putChats(listOf(chat))
        return chat.id.toString()
    }

    override suspend fun leaveChat(chatId: String) {
        val id = chatId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.chats.leaveChat(id) }
        client.store.removeChat(id)
    }

    override suspend fun deleteChat(chatId: String, forEveryone: Boolean) {
        val id = chatId.toLongOrNull() ?: return
        val stored = client.store.state.value.chats[id]
        val time = stored?.lastEventTime?.takeIf { it > 0 }
        MaxCoreGateway.call { client.api.chats.deleteChat(id, time, forEveryone) }
        client.store.removeChat(id)
    }

    override suspend fun clearHistory(chatId: String, forEveryone: Boolean) {
        val id = chatId.toLongOrNull() ?: return
        val stored = client.store.state.value.chats[id]
        val time = stored?.lastEventTime?.takeIf { it > 0 } ?: clock()
        MaxCoreGateway.call {
            client.session.request(Opcode.CHAT_CLEAR, LockPayloads.clearHistory(id, time, forEveryone))
        }
        dropHistory(id)
    }

    /** Сообщения чата убираются локально, сам чат остаётся, превью и непрочитанные сбрасываются. */
    private fun dropHistory(chatId: Long) {
        val state = client.store.state.value
        val chat = state.chats[chatId]
        val ids = ArrayList(state.messagesOf(chatId).map { it.id })
        val last = chat?.lastMessage?.id
        if (last != null && last !in ids) ids.add(last)
        if (chat != null) client.store.putChats(listOf(chat.copy(newMessages = 0)))
        if (ids.isNotEmpty()) {
            client.store.apply(
                MaxEvent.MessagesDeleted(
                    chatId = chatId,
                    messageIds = ids,
                    chat = null,
                    message = null,
                    ttl = false,
                    opcode = Opcode.CHAT_CLEAR.value,
                    raw = null,
                ),
            )
        }
        client.store.closeHistoryGap(chatId)
    }

    override suspend fun botCommands(botId: String): List<BotCommandRow> {
        val id = botId.toLongOrNull() ?: return emptyList()
        val info = MaxCoreGateway.call { client.api.bots.getBotInfo(id) }
        return info.commands.map { BotCommandRow(it.name, it.description.orEmpty()) }
    }

    override suspend fun pressButton(chatId: String, messageId: String, callbackId: String, payload: String?): ButtonAnswer {
        val answer = MaxCoreGateway.call { client.api.bots.pressButton(chatId.toLong(), messageId.toLong(), callbackId, payload) }
        return ButtonAnswer(answer.text, answer.url)
    }

    override fun clear() {
        loaded.value = false
        usersRequested = mutableSetOf()
        mutes.clear()
    }

    companion object {
        private const val TYPING_TICK_MS = 1_000L

        /**
         * Новый список закреплённых для сервера: [wanted] сверху в своём порядке (только те, что
         * закреплены в [current]), остальные закреплённые после них в прежнем порядке.
         */
        fun pinOrder(current: List<Long>, wanted: List<String>): List<Long> {
            val moved = wanted.mapNotNull { it.toLongOrNull() }.distinct().filter { it in current }
            return moved + current.filter { it !in moved }
        }

        /** Сколько публичных чатов просить за раз. */
        const val SEARCH_PAGE_SIZE = 20

        /** Сколько найденных сообщений просить у сервера. */
        const val MESSAGE_SEARCH_COUNT = 50

        /**
         * Тело `MSG_SEND` для нового канала: то же вложение, что у [com.maxly.core.api.ChatsApi.createGroup],
         * но `chatType` — `CHANNEL`, а участников нет. Opcode 63 не используется.
         */
        fun channelCreatePayload(cid: Long, title: String): Map<String, Any?> {
            val attach = linkedMapOf<String, Any?>(
                "_type" to "CONTROL",
                "event" to "new",
                "chatType" to "CHANNEL",
                "title" to title,
                "userIds" to emptyList<Long>(),
            )
            return linkedMapOf("message" to linkedMapOf("cid" to cid, "attaches" to listOf(attach)), "notify" to true)
        }

        /** Локальный `DIALOG`, пока сервер не прислал чат. Первое сообщение создаёт его на сервере. */
        fun dialogPlaceholder(chatId: Long, me: Long?, peerId: Long, title: String): CoreChat {
            val participants = linkedMapOf<String, Any?>()
            if (me != null) participants[me.toString()] = 0L
            participants[peerId.toString()] = 0L
            val name = title.trim().ifEmpty { null }
            val raw = linkedMapOf<String, Any?>(
                "id" to chatId,
                "type" to "DIALOG",
                "status" to "ACTIVE",
                "owner" to me,
                "participantsCount" to participants.size,
                "newMessages" to 0,
                "lastEventTime" to 0L,
                "participants" to participants,
            )
            if (name != null) raw["title"] = name
            return CoreChat(
                id = chatId,
                type = "DIALOG",
                status = "ACTIVE",
                owner = me,
                title = name,
                participantsCount = participants.size,
                newMessages = 0,
                lastEventTime = 0L,
                lastMessage = null,
                raw = raw,
            )
        }

        /**
         * Найденное сервером вместе с совпадениями среди загруженных сообщений: без повторов
         * (у загруженной копии точное время), без пустых и без чата 0, новые сверху.
         */
        fun foundMessages(query: String, server: List<Pair<Long, MaxMessage>>, state: MaxState): List<FoundMessage> {
            val term = query.trim()
            if (term.isEmpty()) return emptyList()
            val local = state.messages.flatMap { (chatId, list) ->
                list.filter { it.text.contains(term, ignoreCase = true) }.map { chatId to it }
            }
            return (local + server)
                .filter { (chatId, message) -> chatId != 0L && message.text.isNotBlank() }
                .distinctBy { (chatId, message) -> chatId to message.id }
                .sortedByDescending { (_, message) -> message.time }
                .map { (chatId, message) ->
                    val sender = message.sender
                    FoundMessage(
                        chatId = chatId.toString(),
                        messageId = message.id.toString(),
                        senderName = sender?.let(state::displayName)?.takeIf { it.isNotBlank() },
                        isOutgoing = sender != null && sender == state.me,
                        text = message.text.trim(),
                        timeMs = message.time,
                    )
                }
        }

        /**
         * Найденный чат или канал. Люди пропускаются: у найденного человека ещё нет чата,
         * который можно открыть. Без названия — по типу: «Канал», «Группа» или «Чат».
         */
        fun searchResultOf(hit: PublicSearchHit): ChatSearchResult? {
            val chat = hit.chat ?: return null
            val type = ChatType.fromCore(chat.type)
            val title = chat.title?.trim().orEmpty().ifEmpty {
                when (type) {
                    ChatType.CHANNEL -> "Канал"
                    ChatType.GROUP -> "Группа"
                    else -> "Чат"
                }
            }
            val subtitle = (chat.mentionName ?: hit.link)?.let { "@$it" } ?: chat.lastMessage?.text?.trim()?.takeIf { it.isNotEmpty() }
            return ChatSearchResult(chat.id.toString(), title, subtitle, type, hit.iconUrl)
        }
    }
}
