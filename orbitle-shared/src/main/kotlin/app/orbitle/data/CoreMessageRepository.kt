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
            val peerRead = chat?.let { ReadMarks.peer(it, state) } ?: 0L
            val stored = state.messagesOf(id).filterNot(MessageMapping::isComment).map { MessageMapping.message(it, id, state, peerRead) }
            stored + queued[chatId].orEmpty()
        }.distinctUntilChanged()
    }

    private val ticks: Flow<Long> = flow {
        while (true) {
            emit(clock())
            delay(1_000)
        }
    }

    private val typists = TypingTracker()

    override suspend fun sendTyping(chatId: String, kind: app.orbitle.domain.TypingKind, postId: String?): Boolean {
        val id = chatId.toLongOrNull() ?: return false
        return client.sendTyping(id, kind.raw, postId?.toLongOrNull())
    }

    override fun header(chatId: String): Flow<ChatHeaderInfo?> {
        val id = chatId.toLongOrNull() ?: 0L
        return combine(client.store.state, client.accountConfig, ticks) { state, config, now ->
            val raw = state.chats[id] ?: return@combine null
            val chat = ChatMapping.chat(raw, state, config, now, mutes = ChatMutes.of(client))
            val peer = ChatMapping.dialogPeer(raw, state.me)
            val seen = PresenceTime.ms(peer?.let { state.presence[it]?.seen })
            val typing = typists.typists(state, id, now) { state.users[it]?.displayName?.takeIf(String::isNotBlank) }
            val bot = peer?.let { state.users[it] }?.takeIf { "BOT" in it.options && com.max.core.api.hasWebApp(it.options) }
            ChatHeaderInfo(chat, participants(raw.raw), seen, typing, botAppId = bot?.id?.toString(), readMarkMs = ReadMarks.own(raw, state))
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

    override suspend fun openLatest(chatId: String) {
        openLatestPage(chatId)
    }

    /** Границы последней свежей страницы: повторное открытие в окне [latestReuseMs] берёт их. */
    private val latestSpans = java.util.concurrent.ConcurrentHashMap<String, HistorySpan>()

    override suspend fun openLatestPage(chatId: String): HistorySpan? {
        val at = latestAt[chatId]
        if (at != null && clock() - at < latestReuseMs) return latestSpans[chatId]
        val id = chatId.toLong()
        val page = MaxCoreGateway.readNow { client.loadHistory(id, from = null, backward = PAGE) }
        latestAt[chatId] = clock()
        resolveSenders(id)
        val span = span(page.messages, reachedOldest = page.messages.size < PAGE / 2, reachedNewest = true)
        if (span != null) latestSpans[chatId] = span else latestSpans.remove(chatId)
        return span
    }

    override suspend fun olderPage(chatId: String, beforeMs: Long): HistorySpan? {
        val id = chatId.toLong()
        // Страницу ждёт листающий читатель: она уходит и во время паузы фоновых чтений
        // после чужого too.many.requests (реакции, счётчики), иначе лента молча вставала.
        val page = MaxCoreGateway.readNow { client.loadHistory(id, from = beforeMs, backward = PAGE) }
        resolveSenders(id)
        val older = page.messages.filter { it.time < beforeMs }
        return span(older, reachedOldest = older.isEmpty()) ?: HistorySpan.START
    }

    override suspend fun newerPage(chatId: String, afterMs: Long): HistorySpan? {
        val id = chatId.toLong()
        val page = MaxCoreGateway.readNow {
            client.api.messages.getChatHistory(id, from = afterMs, forward = PAGE, backward = 0).also { client.store.putHistory(id, it) }
        }
        resolveSenders(id)
        val newer = page.messages.filter { it.time > afterMs }
        return span(newer, reachedNewest = newer.isEmpty() || reachesNewest(id, newer)) ?: HistorySpan(afterMs, afterMs, 0, reachedNewest = true)
    }

    override suspend fun pageAround(chatId: String, timeMs: Long): HistorySpan? {
        val id = chatId.toLong()
        // Чуть больше вперёд: переход показывает цель у верха, ниже — что было после неё.
        val page = MaxCoreGateway.readNow {
            client.api.messages.getChatHistory(id, from = timeMs, forward = AROUND_FORWARD, backward = AROUND_BACKWARD).also { client.store.putHistory(id, it) }
        }
        resolveSenders(id)
        val older = page.messages.count { it.time < timeMs }
        return span(page.messages, reachedOldest = older == 0, reachedNewest = reachesNewest(id, page.messages))
    }

    override suspend fun findMessage(chatId: String, messageId: String): Message? {
        val id = chatId.toLongOrNull() ?: return null
        val mid = messageId.toLongOrNull() ?: return null
        val state = client.store.state.value
        state.messagesOf(id).firstOrNull { it.id == mid }?.let { return MessageMapping.message(it, id, state) }
        val found = MaxCoreGateway.readNow { client.api.messages.getMessages(id, listOf(mid)) }.firstOrNull() ?: return null
        return MessageMapping.message(found, id, client.store.state.value)
    }

    /** Страница дошла до последнего сообщения чата, которое знает список. */
    private fun reachesNewest(chatId: Long, page: List<com.max.core.api.MaxMessage>): Boolean {
        val newest = page.maxOfOrNull { it.time } ?: return false
        val chat = client.store.state.value.chats[chatId] ?: return false
        val last = chat.lastMessage?.time ?: chat.lastEventTime
        return last in 1..newest
    }

    private fun span(page: List<com.max.core.api.MaxMessage>, reachedOldest: Boolean = false, reachedNewest: Boolean = false): HistorySpan? {
        if (page.isEmpty()) return null
        return HistorySpan(page.minOf { it.time }, page.maxOf { it.time }, page.size, reachedOldest, reachedNewest)
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
        enqueueText(chatId, text, replyTo, marks)

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
        val outcome = forwardMessages(chatId, listOf(messageId), targetChatId)
        outcome.error?.let { throw CoreErrors.map(it) }
    }

    /**
     * Пересылка выбранного ([MaxClient.forwardMessages]): ядро шлёт по одному, от старых к новым,
     * кладёт ушедшие копии в стор и останавливается на первой ошибке.
     */
    override suspend fun forwardMessages(chatId: String, messageIds: List<String>, targetChatId: String): ForwardOutcome {
        val ids = messageIds.mapNotNull { it.toLongOrNull() }
        if (ids.isEmpty()) return ForwardOutcome(0, 0, null)
        val batch = MaxCoreGateway.call { client.forwardMessages(targetChatId.toLong(), chatId.toLong(), ids) }
        return ForwardOutcome(batch.sent.size, ids.size, batch.error?.let(CoreErrors::map))
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

    private val pendingNotes = java.util.concurrent.ConcurrentHashMap<String, app.orbitle.domain.VideoNoteRecording>()

    override suspend fun sendVideoNote(chatId: String, recording: app.orbitle.domain.VideoNoteRecording, replyTo: String?) {
        val note = app.orbitle.domain.VideoContent(
            "local-note", "file://${recording.path}",
            width = recording.side, height = recording.side, durationMs = recording.durationMs, isRound = true,
        )
        val local = Message(
            id = "local-${localIds.incrementAndGet()}",
            chatId = chatId,
            authorId = currentUserId.orEmpty(),
            text = "",
            timeMs = clock(),
            status = MessageStatus.SENDING,
            content = MessageContent(reply = replyTo?.let { replyPreview(chatId, it) }, attachments = listOf(ChatAttachment.Video(note))),
        )
        pendingNotes[local.id] = recording
        put(chatId, local)
        deliver(chatId, local, replyTo)
    }

    /** Загрузка кружка (слот видеосообщения) и одно сообщение с ним. */
    private suspend fun uploadVideoNote(chatId: String, recording: app.orbitle.domain.VideoNoteRecording, replyTo: String?, progress: (Float) -> Unit) {
        val source = com.max.core.media.fileUploadSource(recording.path)
        val note = try {
            client.media.uploadVideoNote(source, recording.fileName, recording.durationMs.takeIf { it > 0 }) { sent, total ->
                if (total > 0) progress((sent.toFloat() / total).coerceIn(0f, 1f))
            }
        } finally {
            runCatching { source.close() }
        }
        client.sendAttachments(chatId.toLong(), listOf(note), null, replyTo?.toLongOrNull())
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
            val note = pendingNotes[local.id]
            withContext(NonCancellable) {
                if (recording != null) {
                    MaxCoreGateway.call { uploadVoice(chatId, recording, replyTo, progress) }
                } else if (note != null) {
                    MaxCoreGateway.call { uploadVideoNote(chatId, note, replyTo, progress) }
                } else if (media == null) {
                    val elements = TextMarks.toElements(local.text, local.content.formatting)
                    MaxCoreGateway.call { client.sendFormattedText(chatId.toLong(), local.text, elements, replyTo?.toLongOrNull()) }
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
            pendingNotes.remove(local.id)?.let { java.io.File(it.path).delete() }
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
        pendingNotes.remove(localId)?.let { java.io.File(it.path).delete() }
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

    override suspend fun edit(chatId: String, messageId: String, text: String) = editFormatted(chatId, messageId, text, emptyList())

    override suspend fun editFormatted(chatId: String, messageId: String, text: String, marks: List<TextSpan>) {
        // Весь список разом: пустой снимает разметку. Свою правку ядро само кладёт в стор.
        MaxCoreGateway.call { client.editText(chatId.toLong(), messageId.toLong(), text, TextMarks.toElements(text, marks)) }
    }

    override suspend fun delete(chatId: String, messageIds: List<String>, forEveryone: Boolean) {
        deleteMessages(chatId, messageIds, forEveryone)
    }

    /**
     * Весь выбор одним `MSG_DELETE` ([MaxClient.deleteMessages]): стор ядра убирает только то, что
     * сервер удалил, оставленные им id приходят в [DeleteOutcome.failed]. Не ушедшие сообщения
     * убираются локально и считаются удалёнными.
     */
    override suspend fun deleteMessages(chatId: String, messageIds: List<String>, forEveryone: Boolean): DeleteOutcome {
        val local = messageIds.filter { it.startsWith("local-") }
        local.forEach { remove(chatId, it) }
        val ids = messageIds.mapNotNull { it.toLongOrNull() }
        if (ids.isEmpty()) return DeleteOutcome(local, emptyList())
        val result = MaxCoreGateway.call { client.deleteMessages(chatId.toLong(), ids, forMe = !forEveryone) }
        return DeleteOutcome(local + result.deleted.map { it.toString() }, result.failed.map { it.toString() })
    }

    /** Отметка уходит временем самого сообщения ([ReadMarks.send]), а не часами устройства. */
    override suspend fun markRead(chatId: String, messageId: String) {
        val id = chatId.toLong()
        val message = messageId.toLongOrNull() ?: return
        ReadMarks.send(client, id, message)
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

    override suspend fun messageReaders(chatId: String, messageId: String): List<app.orbitle.domain.MessageReader>? {
        val id = chatId.toLong()
        if (!client.isMessageReadersAvailable(id)) return null
        val readers = MaxCoreGateway.call { client.loadMessageReaders(id, messageId.toLong()) }
        // Ядро освежило сведения о чате: группа могла вырасти или в ней идёт звонок.
        if (readers.isEmpty() && !client.isMessageReadersAvailable(id)) return null
        val known = client.store.state.value.users
        return readers.map { MessageMapping.reader(it, known[it.userId]) }
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
        /** Окно перехода к далёкому сообщению: столько до него и после. */
        const val AROUND_BACKWARD = 15
        const val AROUND_FORWARD = 30
        const val REACTIONS = 100
    }
}
