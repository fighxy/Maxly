package app.orbitle.data

import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.Message
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.OutgoingFile
import app.orbitle.domain.PhotoContent
import app.orbitle.domain.VideoContent
import app.orbitle.domain.FileContent
import com.max.core.media.OutgoingMedia
import app.orbitle.domain.MessageContent
import app.orbitle.domain.MessageReply
import app.orbitle.domain.MessageStatus
import com.max.core.api.Transcription
import com.max.core.events.MaxEvent
import com.max.core.protocol.Opcode
import com.max.shared.MaxClient
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.update
import java.util.concurrent.atomic.AtomicLong

/** [MessageRepository] над стором `MaxClient`: история и события ядра плюс своя очередь отправки. */
class CoreMessageRepository(
    private val client: MaxClient,
    private val clock: () -> Long = System::currentTimeMillis,
) : MessageRepository {

    /** Свои сообщения, которых ещё нет на сервере: id чата → сообщения. */
    private val pending = MutableStateFlow<Map<String, List<Message>>>(emptyMap())
    private val localIds = AtomicLong(0)

    override val currentUserId: String? get() = client.store.state.value.me?.toString()

    override fun messages(chatId: String): Flow<List<Message>> {
        val id = chatId.toLongOrNull() ?: 0L
        return combine(client.store.state, pending) { state, queued ->
            val chat = state.chats[id]
            val peerRead = maxOf(
                chat?.let { ChatMapping.peerReadMark(it, state.me) } ?: 0L,
                state.readMarks[id].orEmpty().filterKeys { it != state.me }.values.maxOrNull() ?: 0L,
            )
            val stored = state.messagesOf(id).map { MessageMapping.message(it, id, state, peerRead) }
            stored + queued[chatId].orEmpty()
        }.distinctUntilChanged()
    }

    private val ticks: Flow<Long> = flow {
        while (true) {
            emit(clock())
            delay(1_000)
        }
    }

    override fun header(chatId: String): Flow<ChatHeaderInfo?> {
        val id = chatId.toLongOrNull() ?: 0L
        return combine(client.store.state, client.accountConfig, ticks) { state, config, now ->
            val raw = state.chats[id] ?: return@combine null
            val chat = ChatMapping.chat(raw, state, config, now)
            val peer = ChatMapping.dialogPeer(raw, state.me)
            val seen = peer?.let { state.presence[it]?.seen }?.let { if (it < 100_000_000_000L) it * 1000 else it } ?: 0L
            val typing = state.typingUsers(id, now).filter { it != state.me }
                .map { state.users[it]?.displayName?.takeIf(String::isNotBlank) ?: "Кто-то" }
            ChatHeaderInfo(chat, participants(raw.raw), seen, typing)
        }.distinctUntilChanged()
    }

    private fun participants(raw: Map<*, *>): Int? {
        ChatMapping.longOf(raw["participantsCount"])?.let { return it.toInt() }
        return (raw["participants"] as? Map<*, *>)?.size?.takeIf { it > 0 }
    }

    override suspend fun loadLatest(chatId: String) {
        val id = chatId.toLong()
        MaxCoreGateway.call { client.loadHistory(id, from = null, backward = PAGE) }
        resolveSenders(id)
    }

    override suspend fun loadOlder(chatId: String): Boolean {
        val id = chatId.toLong()
        val oldest = client.store.state.value.messagesOf(id).minByOrNull { it.time } ?: return false
        val before = client.store.state.value.messagesOf(id).size
        val page = MaxCoreGateway.call { client.loadHistory(id, from = oldest.time, backward = PAGE) }
        resolveSenders(id)
        val grown = client.store.state.value.messagesOf(id).size > before
        return grown && page.messages.any { it.id != oldest.id }
    }

    /** Имена авторов групп: неизвестных пользователей спросить у сервера. */
    private suspend fun resolveSenders(chatId: Long) {
        val state = client.store.state.value
        val unknown = state.messagesOf(chatId).mapNotNull { it.sender }.distinct().filter { it !in state.users }
        if (unknown.isEmpty()) return
        runCatching { MaxCoreGateway.call { client.loadUsers(unknown.take(100)) } }
    }

    override suspend fun send(chatId: String, text: String, replyTo: String?) {
        val local = Message(
            id = "local-${localIds.incrementAndGet()}",
            chatId = chatId,
            authorId = currentUserId.orEmpty(),
            text = text,
            timeMs = clock(),
            status = MessageStatus.SENDING,
            content = MessageContent(reply = replyTo?.let { replyPreview(chatId, it) }),
        )
        put(chatId, local)
        deliver(chatId, local, replyTo)
    }

    override suspend fun sendSticker(chatId: String, sticker: app.orbitle.domain.Sticker, replyTo: String?) {
        MaxCoreGateway.call { client.sendSticker(chatId.toLong(), sticker.id.toLong(), replyTo?.toLongOrNull()) }
    }

    override suspend fun forward(chatId: String, messageId: String, targetChatId: String) {
        val target = targetChatId.toLong()
        MaxCoreGateway.call {
            // Свои сообщения сервер не присылает обратно: копию в целевом чате кладём сами.
            val sent = client.api.messages.forwardMessage(target, messageId.toLong(), sourceChatId = chatId.toLong())
            client.store.putSentMessage(target, sent)
        }
    }

    /** Вложения не ушедших сообщений: нужны для повтора. */
    private val pendingMedia = java.util.concurrent.ConcurrentHashMap<String, List<OutgoingFile>>()

    override suspend fun sendMedia(chatId: String, items: List<OutgoingFile>, caption: String, replyTo: String?, progress: (Float) -> Unit) {
        val local = Message(
            id = "local-${localIds.incrementAndGet()}",
            chatId = chatId,
            authorId = currentUserId.orEmpty(),
            text = caption,
            timeMs = clock(),
            status = MessageStatus.SENDING,
            content = MessageContent(reply = replyTo?.let { replyPreview(chatId, it) }, attachments = items.mapIndexed(::localAttachment)),
        )
        pendingMedia[local.id] = items
        put(chatId, local)
        deliver(chatId, local, replyTo, progress)
    }

    private fun localAttachment(index: Int, item: OutgoingFile): ChatAttachment {
        val id = "local-$index"
        val uri = "file://${item.path}"
        return when (item.kind) {
            OutgoingFile.Kind.PHOTO -> ChatAttachment.Photo(PhotoContent(id, uri, item.width, item.height))
            OutgoingFile.Kind.VIDEO -> ChatAttachment.Video(VideoContent(id, uri, width = item.width, height = item.height))
            OutgoingFile.Kind.FILE -> ChatAttachment.File(FileContent(id, item.name, item.size))
        }
    }

    private fun replyPreview(chatId: String, messageId: String): MessageReply? {
        val state = client.store.state.value
        val id = chatId.toLongOrNull() ?: return null
        val source = state.messagesOf(id).firstOrNull { it.id.toString() == messageId } ?: return null
        val message = MessageMapping.message(source, id, state)
        return MessageReply(messageId, message.authorName.ifEmpty { "Сообщение" }, message.replySnippet, message.replyKind)
    }

    private suspend fun deliver(chatId: String, local: Message, replyTo: String?, progress: (Float) -> Unit = {}) {
        // Уход с экрана не должен обрывать отправку на полпути.
        try {
            val media = pendingMedia[local.id]
            withContext(NonCancellable) {
                if (media == null) {
                    MaxCoreGateway.call { client.sendText(chatId.toLong(), local.text, replyTo?.toLongOrNull()) }
                } else {
                    val outgoing = media.map { OutgoingMedia(it.path, coreKind(it.kind), it.name) }
                    MaxCoreGateway.call {
                        client.sendMedia(chatId.toLong(), outgoing, local.text.takeIf { it.isNotBlank() }, replyTo?.toLongOrNull()) { sent, total ->
                            if (total > 0) progress((sent.toFloat() / total).coerceIn(0f, 1f))
                        }
                    }
                }
            }
            pendingMedia.remove(local.id)
            remove(chatId, local.id)
        } catch (failure: Exception) {
            put(chatId, local.copy(status = MessageStatus.FAILED))
            throw failure
        }
    }

    override suspend fun retry(chatId: String, localId: String) {
        val message = pending.value[chatId]?.firstOrNull { it.id == localId } ?: return
        val sending = message.copy(status = MessageStatus.SENDING, timeMs = clock())
        put(chatId, sending)
        deliver(chatId, sending, message.content.reply?.messageId)
    }

    override fun discard(chatId: String, localId: String) {
        pendingMedia.remove(localId)
        remove(chatId, localId)
    }

    private fun coreKind(kind: OutgoingFile.Kind) = when (kind) {
        OutgoingFile.Kind.PHOTO -> OutgoingMedia.Kind.PHOTO
        OutgoingFile.Kind.VIDEO -> OutgoingMedia.Kind.VIDEO
        OutgoingFile.Kind.FILE -> OutgoingMedia.Kind.FILE
    }

    private fun put(chatId: String, message: Message) = pending.update { all ->
        val list = all[chatId].orEmpty().filterNot { it.id == message.id } + message
        all + (chatId to list.sortedBy { it.timeMs })
    }

    private fun remove(chatId: String, localId: String) = pending.update { all ->
        val list = all[chatId].orEmpty().filterNot { it.id == localId }
        if (list.isEmpty()) all - chatId else all + (chatId to list)
    }

    override suspend fun edit(chatId: String, messageId: String, text: String) {
        val edited = MaxCoreGateway.call { client.api.messages.editMessage(chatId.toLong(), messageId.toLong(), text) }
        // Своя правка сервером обратно не присылается.
        client.store.apply(MaxEvent.MessageEdited(edited.copy(chatId = edited.chatId ?: chatId.toLong()), 0, null))
    }

    override suspend fun delete(chatId: String, messageIds: List<String>, forEveryone: Boolean) {
        val ids = messageIds.mapNotNull { it.toLongOrNull() }
        messageIds.filter { it.startsWith("local-") }.forEach { remove(chatId, it) }
        if (ids.isEmpty()) return
        MaxCoreGateway.call { client.api.messages.deleteMessages(chatId.toLong(), ids, forMe = !forEveryone) }
        client.store.apply(MaxEvent.MessagesDeleted(chatId.toLong(), ids, null, null, false, 0, null))
    }

    override suspend fun markRead(chatId: String, messageId: String) {
        val id = chatId.toLong()
        val message = messageId.toLongOrNull() ?: return
        val state = MaxCoreGateway.call { client.api.messages.markRead(id, message) }
        val me = client.store.state.value.me ?: return
        client.store.apply(MaxEvent.MessageRead(id, me, state.mark, false, 0, null))
    }

    override suspend fun react(chatId: String, messageId: String, emoji: String?) {
        MaxCoreGateway.call { client.setReaction(chatId.toLong(), messageId.toLong(), emoji) }
    }

    override suspend fun reactionUsers(chatId: String, messageId: String): List<app.orbitle.domain.ReactionUser> {
        val users = MaxCoreGateway.call { client.loadReactionUsers(chatId.toLong(), messageId.toLong()) }
        val known = client.store.state.value.users
        return users.map { entry ->
            val user = known[entry.userId]
            app.orbitle.domain.ReactionUser(
                userId = entry.userId.toString(),
                name = user?.displayName.orEmpty(),
                avatarUrl = user?.baseUrl?.takeIf { it.isNotBlank() },
                emoji = entry.reaction,
            )
        }
    }

    override suspend fun reactionCatalog(): List<String> =
        runCatching { MaxCoreGateway.call { client.reactionCatalog() } }.getOrDefault(emptyList()).map { it.emoji }.filter { it.isNotEmpty() }

    override suspend fun transcribe(chatId: String, messageId: String, voiceId: String): String? {
        val result = MaxCoreGateway.call { client.transcribe(chatId.toLong(), messageId.toLong(), voiceId.toLong()) }
        return when (result.status) {
            1 -> result.text.orEmpty()
            0 -> null
            else -> throw OrbitleError.Rejected("Не удалось расшифровать голосовое")
        }
    }

    override fun transcriptions(): Flow<Pair<String, String>> = client.events.all.mapNotNull { event ->
        if (event !is MaxEvent.Unknown || event.opcode != Opcode.TRANSCRIPTION_RESULT.value) return@mapNotNull null
        val result = Transcription.from(event.raw) ?: return@mapNotNull null
        val messageId = result.messageId ?: return@mapNotNull null
        if (result.status != 1) return@mapNotNull null
        messageId.toString() to result.text.orEmpty()
    }

    override suspend fun mediaLink(chatId: String, messageId: String, attachment: ChatAttachment): String {
        val chat = chatId.toLong()
        val message = messageId.toLong()
        return when (attachment) {
            is ChatAttachment.Video -> MaxCoreGateway.call { client.media.getVideoLink(chat, message, attachment.video.id.toLong()) }.url
                ?: throw OrbitleError.Rejected("Видео недоступно")
            is ChatAttachment.File -> MaxCoreGateway.call { client.media.getFileLink(chat, message, attachment.file.id.toLong()) }.url
            else -> throw OrbitleError.Rejected("Вложение недоступно")
        }
    }

    /** User-Agent сессии: адреса видео и файлов CDN выдаёт под Android-клиента. */
    val mediaUserAgent: String get() = client.config.userAgent.httpUserAgent

    private companion object {
        const val PAGE = 40
    }
}
