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
import app.orbitle.domain.TextSpan
import com.max.core.api.Transcription
import com.max.core.events.MaxEvent
import com.max.core.protocol.Opcode
import com.max.shared.MaxClient
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
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
    /**
     * Сколько миллисекунд последняя страница чата не перезапрашивается: повторное открытие чата
     * в это окно берёт стор. На частые `CHAT_HISTORY` сервер отвечает `too.many.requests`,
     * а новые сообщения в это время всё равно приходят пушами.
     */
    private val latestReuseMs: Long = 10_000,
) : MessageRepository {

    /** Когда последняя страница чата в последний раз пришла с сервера. */
    private val latestAt = java.util.concurrent.ConcurrentHashMap<String, Long>()

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
        val at = latestAt[chatId]
        if (at != null && clock() - at < latestReuseMs) return
        refreshLatest(chatId)
    }

    override suspend fun refreshLatest(chatId: String) {
        val id = chatId.toLong()
        MaxCoreGateway.read { client.loadHistory(id, from = null, backward = PAGE) }
        latestAt[chatId] = clock()
        resolveSenders(id)
    }

    override suspend fun loadOlder(chatId: String): Boolean {
        val id = chatId.toLong()
        val oldest = client.store.state.value.messagesOf(id).minByOrNull { it.time } ?: return false
        val before = client.store.state.value.messagesOf(id).size
        val page = MaxCoreGateway.read { client.loadHistory(id, from = oldest.time, backward = PAGE) }
        resolveSenders(id)
        val grown = client.store.state.value.messagesOf(id).size > before
        return grown && page.messages.any { it.id != oldest.id }
    }

    /** Имена авторов групп: неизвестных пользователей спросить у сервера. */
    private suspend fun resolveSenders(chatId: Long) {
        val state = client.store.state.value
        val unknown = state.messagesOf(chatId).mapNotNull { it.sender }.distinct().filter { it !in state.users }
        if (unknown.isEmpty()) return
        runCatching { MaxCoreGateway.read { client.loadUsers(unknown.take(100)) } }
    }

    override suspend fun send(chatId: String, text: String, replyTo: String?) = enqueueText(chatId, text, replyTo, emptyList())

    override suspend fun sendFormatted(chatId: String, text: String, replyTo: String?, marks: List<TextSpan>) =
        enqueueText(chatId, text, replyTo, marks.filter { it.kind == TextSpan.Kind.ANIMOJI || it.kind == TextSpan.Kind.MENTION })

    private suspend fun enqueueText(chatId: String, text: String, replyTo: String?, marks: List<TextSpan>) {
        val local = Message(
            id = "local-${localIds.incrementAndGet()}",
            chatId = chatId,
            authorId = currentUserId.orEmpty(),
            text = text,
            timeMs = clock(),
            status = MessageStatus.SENDING,
            content = MessageContent(reply = replyTo?.let { replyPreview(chatId, it) }, formatting = marks),
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

    /** Идущие загрузки вложений по id своего сообщения: их можно отменить. */
    private val uploads = java.util.concurrent.ConcurrentHashMap<String, kotlinx.coroutines.Job>()
    /** Загрузки живут дольше экрана: уход из чата их не обрывает. */
    private val uploadScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Default)

    override fun cancelUpload(chatId: String, localId: String) {
        uploads.remove(localId)?.cancel()
        discard(chatId, localId)
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

    /** Голосовые не ушедших сообщений: нужны для повтора. */
    private val pendingVoice = java.util.concurrent.ConcurrentHashMap<String, app.orbitle.domain.VoiceRecording>()

    override suspend fun sendVoice(chatId: String, recording: app.orbitle.domain.VoiceRecording, replyTo: String?) {
        val voice = app.orbitle.domain.VoiceContent("local-voice", "file://${recording.path}", recording.waveform, recording.durationMs)
        val local = Message(
            id = "local-${localIds.incrementAndGet()}",
            chatId = chatId,
            authorId = currentUserId.orEmpty(),
            text = "",
            timeMs = clock(),
            status = MessageStatus.SENDING,
            content = MessageContent(reply = replyTo?.let { replyPreview(chatId, it) }, attachments = listOf(ChatAttachment.Voice(voice))),
        )
        pendingVoice[local.id] = recording
        put(chatId, local)
        deliver(chatId, local, replyTo)
    }

    /** Загрузка голосового и одно сообщение с ним; волна уходит столбиками 0…120. */
    private suspend fun uploadVoice(chatId: String, recording: app.orbitle.domain.VoiceRecording, replyTo: String?, progress: (Float) -> Unit) {
        val bytes = java.io.File(recording.path).readBytes()
        val uploaded = client.media.uploadVoice(bytes, recording.fileName, recording.durationMs) { sent, total ->
            if (total > 0) progress((sent.toFloat() / total).coerceIn(0f, 1f))
        }
        val wave = ByteArray(recording.waveform.size) { recording.waveform[it].coerceIn(0, 255).toByte() }
        val attachment = if (wave.isEmpty()) uploaded else uploaded.copy(wave = wave)
        client.sendAttachments(chatId.toLong(), listOf(attachment), null, replyTo?.toLongOrNull())
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
            val recording = pendingVoice[local.id]
            withContext(NonCancellable) {
                if (recording != null) {
                    MaxCoreGateway.call { uploadVoice(chatId, recording, replyTo, progress) }
                } else if (media == null) {
                    val elements = animojiElements(local.text, local.content.formatting) +
                        LockPayloads.mentionElements(local.text, local.content.formatting)
                    MaxCoreGateway.call { client.sendText(chatId.toLong(), local.text, replyTo?.toLongOrNull(), elements) }
                } else {
                    val outgoing = media.map { OutgoingMedia(it.path, coreKind(it.kind), it.name) }
                    val work = uploadScope.async {
                        MaxCoreGateway.call {
                            client.sendMedia(chatId.toLong(), outgoing, local.text.takeIf { it.isNotBlank() }, replyTo?.toLongOrNull()) { sent, total ->
                                if (total > 0) progress((sent.toFloat() / total).coerceIn(0f, 1f))
                            }
                        }
                    }
                    uploads[local.id] = work
                    try {
                        work.await()
                    } catch (e: kotlinx.coroutines.CancellationException) {
                        // Отменили кнопкой: сообщение уже убрано, это не ошибка.
                        if (work.isCancelled) return@withContext
                        throw e
                    } finally {
                        uploads.remove(local.id)
                    }
                }
            }
            pendingMedia.remove(local.id)
            pendingVoice.remove(local.id)?.let { java.io.File(it.path).delete() }
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
        pendingVoice.remove(localId)?.let { java.io.File(it.path).delete() }
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

    override suspend fun pin(chatId: String, messageId: String) {
        val chat = chatId.toLongOrNull() ?: return
        val message = messageId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.messages.pinMessage(chat, message) }
    }

    override suspend fun schedule(chatId: String, text: String, sendAt: Long) {
        val chat = chatId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.messages.scheduleMessage(chat, text, sendAt) }
    }

    override suspend fun scheduled(chatId: String): List<app.orbitle.domain.FoundMessage> {
        val chat = chatId.toLongOrNull() ?: return emptyList()
        val page = MaxCoreGateway.call {
            client.api.messages.getChatHistory(chat, itemType = com.max.core.api.HistoryItemType.DELAYED)
        }
        val me = client.store.state.value.me
        return page.messages.map { message ->
            app.orbitle.domain.FoundMessage(
                chatId = chatId,
                messageId = message.id.toString(),
                senderName = null,
                isOutgoing = message.sender != null && message.sender == me,
                text = message.text.trim(),
                timeMs = message.time,
            )
        }
    }

    override suspend fun sendPoll(chatId: String, title: String, answers: List<String>) {
        val chat = chatId.toLongOrNull() ?: return
        val options = answers.map { com.max.core.api.PollAnswer(it) }
        val sent = MaxCoreGateway.call {
            client.api.messages.sendPoll(chat, com.max.core.media.OutgoingAttachment.Poll(title, options))
        }
        client.store.putSentMessage(chat, sent)
    }

    override suspend fun votePoll(chatId: String, messageId: String, pollId: String, answerId: String) {
        val chat = chatId.toLongOrNull() ?: return
        val message = messageId.toLongOrNull() ?: return
        val poll = pollId.toLongOrNull() ?: return
        val answer = answerId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.api.messages.votePoll(chat, message, poll, listOf(answer)) }
    }

    override suspend fun searchInChat(chatId: String, query: String): List<app.orbitle.domain.FoundMessage> {
        val chat = chatId.toLongOrNull() ?: return emptyList()
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        val packet = MaxCoreGateway.call {
            client.session.request(Opcode.MSG_SEARCH, LockPayloads.inChatSearch(chat, term))
        }
        val me = client.store.state.value.me
        return LockPayloads.foundMessages(chat, (packet.payload as? Map<*, *>)?.get("result"), me)
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

    /** Стор ядро обновляет само: отметка прочтения и счётчик сервера. */
    override suspend fun markUnread(chatId: String, fromMs: Long): Int =
        MaxCoreGateway.call { client.markUnread(chatId.toLong(), fromMs) }

    /** Сообщения, чья реакция ещё ждёт сервер: сверка 180 их не перебивает. */
    private val pendingReactions = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    override suspend fun react(chatId: String, messageId: String, emoji: String?) {
        val key = "$chatId:$messageId"
        pendingReactions += key
        try {
            MaxCoreGateway.call { client.setReaction(chatId.toLong(), messageId.toLong(), emoji) }
        } finally {
            pendingReactions -= key
        }
    }

    override suspend fun syncReactions(chatId: String, messageIds: List<String>) {
        val chat = chatId.toLongOrNull() ?: return
        val ids = messageIds.mapNotNull { it.toLongOrNull() }.distinct()
        for (chunk in ids.chunked(REACTIONS)) {
            // Пустой ответ и запись без счётчиков не значат «реакций нет»: ядро иначе стёрло бы их.
            val found = MaxCoreGateway.read { client.api.messages.getReactions(chat, chunk) } ?: continue
            for ((key, info) in found) {
                val id = key.toLongOrNull() ?: continue
                if (info.counters.none { it.count > 0 }) continue
                if ("$chatId:$id" in pendingReactions) continue
                client.store.putReactions(chat, id, info)
            }
        }
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

    /** Отметки `ANIMOJI`: `{type, from, length, entityId, attributes.animojiLottieUrl}`, смещения UTF-16. */
    private fun animojiElements(text: String, spans: List<TextSpan>): List<Map<String, Any?>> = spans.mapNotNull { span ->
        if (span.kind != TextSpan.Kind.ANIMOJI) return@mapNotNull null
        val id = span.entityId?.toLongOrNull() ?: return@mapNotNull null
        if (span.from < 0 || span.length <= 0 || span.from + span.length > text.length) return@mapNotNull null
        linkedMapOf<String, Any?>(
            "type" to "ANIMOJI",
            "from" to span.from,
            "length" to span.length,
            "entityId" to id,
            "attributes" to linkedMapOf("animojiLottieUrl" to span.url.orEmpty()),
        )
    }

    private companion object {
        const val PAGE = 40
        const val REACTIONS = 100
    }
}
