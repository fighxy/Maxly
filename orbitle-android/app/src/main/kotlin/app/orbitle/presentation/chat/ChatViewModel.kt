package app.orbitle.presentation.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.MessageRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.OutgoingFile
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.chatlist.ChatListFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Строка ленты. Лента идёт от новых к старым: экран рисует её перевёрнутой. */
sealed interface ChatItem {
    val key: String

    data class Day(override val key: String, val label: String) : ChatItem

    data class Service(override val key: String, val text: String) : ChatItem

    data class Bubble(
        val message: Message,
        val outgoing: Boolean,
        val time: String,
        /** Имя автора над пузырём (группы, первое сообщение подряд). */
        val authorName: String?,
        val authorColor: Int,
        /** Аватар автора слева (группы, последнее сообщение подряд). */
        val showsAvatar: Boolean,
        val avatar: ChatAvatar?,
        /** Следующее сообщение того же автора: хвост пузыря не рисуется. */
        val continues: Boolean,
        val isGroupChat: Boolean,
    ) : ChatItem {
        override val key: String get() = message.id
    }
}

data class ChatHeaderUi(
    val title: String,
    val subtitle: String,
    val subtitleAccent: Boolean,
    val avatar: ChatAvatar,
    val isVerified: Boolean = false,
)

data class ChatUiState(
    val header: ChatHeaderUi? = null,
    val items: List<ChatItem> = emptyList(),
    val draft: String = "",
    val replyTo: Message? = null,
    val editing: Message? = null,
    val canWrite: Boolean = true,
    val isLoading: Boolean = true,
    val isLoadingOlder: Boolean = false,
    val hasOlder: Boolean = true,
    /** Пустой загруженный чат: подсказка вместо ленты. */
    val emptyHint: String? = null,
    val quickReactions: List<String> = ReactionPalette.FALLBACK,
    val reactionCatalog: List<String> = emptyList(),
    val unreadBelow: Int = 0,
    /** Выбранные вложения: уйдут одним сообщением с текстом поля как подписью. */
    val attachments: List<OutgoingFile> = emptyList(),
    /** Доля загрузки отправляемых вложений, `null` — ничего не грузится. */
    val uploadProgress: Float? = null,
) {
    val canSend: Boolean get() = draft.isNotBlank() || attachments.isNotEmpty()
}

/** Экран переписки: лента, поле ввода, ответ, правка, удаление, реакции. */
class ChatViewModel(
    val chatId: String,
    private val repository: MessageRepository,
    private val formatter: ChatFormatter = ChatFormatter(),
    private val now: () -> Long = System::currentTimeMillis,
    /** Название, пока чата нет в сторе (новый диалог из контактов). */
    private val fallbackTitle: String? = null,
    voicePlayer: VoicePlayer? = null,
    files: MessageFiles? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(ChatUiState())
    val state: StateFlow<ChatUiState> = _state.asStateFlow()

    private val _messages = MutableStateFlow<String?>(null)
    /** Ошибки и уведомления для снекбара. */
    val messages: StateFlow<String?> = _messages.asStateFlow()

    /** Голосовые, расшифровка, просмотр фото и видео, файлы. */
    val media = ChatMedia(chatId, repository, viewModelScope, voicePlayer, files, onError = { show(it) })

    private var history: List<Message> = emptyList()
    private var header: ChatHeaderInfo? = null
    private var latestLoaded = false
    private var markedReadId: String? = null
    private var active = true
    private var draftBeforeEdit = ""
    private var builtFor: ChatType? = null

    init {
        viewModelScope.launch {
            repository.messages(chatId).collect {
                history = it
                rebuild()
                markRead()
            }
        }
        viewModelScope.launch {
            repository.header(chatId).collect {
                header = it
                rebuildHeader()
            }
        }
        viewModelScope.launch {
            val catalog = repository.reactionCatalog()
            if (catalog.isNotEmpty()) _state.update { it.copy(reactionCatalog = catalog, quickReactions = ReactionPalette.quick(catalog)) }
        }
        loadLatest()
    }

    fun loadLatest() {
        viewModelScope.launch {
            try {
                repository.loadLatest(chatId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
            latestLoaded = true
            _state.update { it.copy(isLoading = false) }
            rebuild()
        }
    }

    fun loadOlder() {
        val current = _state.value
        if (current.isLoadingOlder || !current.hasOlder || !latestLoaded || history.isEmpty()) return
        _state.update { it.copy(isLoadingOlder = true) }
        viewModelScope.launch {
            val more = try {
                repository.loadOlder(chatId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
                true
            }
            _state.update { it.copy(isLoadingOlder = false, hasOlder = more) }
        }
    }

    /** Экран виден: можно отмечать прочитанным. */
    fun setActive(value: Boolean) {
        active = value
        if (value) markRead()
    }

    fun setDraft(text: String) = _state.update { it.copy(draft = text) }

    /** Добавить выбранные вложения; сверх лимита — подсказка. */
    fun addAttachments(items: List<OutgoingFile>) {
        if (items.isEmpty()) return
        if (_state.value.editing != null) cancelEdit()
        val current = _state.value.attachments
        val merged = (current + items).distinctBy { it.path }
        if (merged.size > OutgoingFile.LIMIT) _messages.value = "Можно отправить не больше ${OutgoingFile.LIMIT} вложений за раз"
        _state.update { it.copy(attachments = merged.take(OutgoingFile.LIMIT)) }
    }

    fun removeAttachment(item: OutgoingFile) = _state.update { it.copy(attachments = it.attachments.filterNot { a -> a.path == item.path }) }

    fun send() {
        val text = _state.value.draft.trim()
        val attachments = _state.value.attachments
        if (attachments.isNotEmpty() && _state.value.editing == null) {
            sendAttachments(attachments, text)
            return
        }
        if (text.isEmpty()) return
        _state.value.editing?.let { saveEdit(it, text); return }
        val reply = _state.value.replyTo
        _state.update { it.copy(draft = "", replyTo = null) }
        viewModelScope.launch {
            try {
                repository.send(chatId, text, reply?.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    private fun sendAttachments(items: List<OutgoingFile>, caption: String) {
        val reply = _state.value.replyTo
        _state.update { it.copy(draft = "", replyTo = null, attachments = emptyList(), uploadProgress = 0f) }
        viewModelScope.launch {
            try {
                repository.sendMedia(chatId, items, caption, reply?.id) { fraction ->
                    _state.update { it.copy(uploadProgress = fraction) }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            } finally {
                _state.update { it.copy(uploadProgress = null) }
            }
        }
    }

    fun retry(message: Message) {
        viewModelScope.launch {
            try {
                repository.retry(chatId, message.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun isOutgoing(message: Message): Boolean {
        val me = repository.currentUserId
        return !me.isNullOrEmpty() && message.authorId == me
    }

    // Ответ

    fun beginReply(message: Message) {
        if (_state.value.editing != null) cancelEdit()
        if (!isServer(message)) return
        _state.update { it.copy(replyTo = message) }
    }

    fun cancelReply() = _state.update { it.copy(replyTo = null) }

    // Правка

    fun canEdit(message: Message): Boolean =
        isOutgoing(message) && isServer(message) && message.content.forward == null && message.text.isNotBlank() && !message.isService

    fun beginEdit(message: Message) {
        if (!canEdit(message)) return
        _state.update {
            if (it.editing == null) draftBeforeEdit = it.draft
            it.copy(editing = message, replyTo = null, draft = message.text)
        }
    }

    fun cancelEdit() {
        if (_state.value.editing == null) return
        _state.update { it.copy(editing = null, draft = draftBeforeEdit) }
        draftBeforeEdit = ""
    }

    private fun saveEdit(target: Message, text: String) {
        val restore = draftBeforeEdit
        draftBeforeEdit = ""
        _state.update { it.copy(editing = null, draft = restore) }
        if (text == target.text.trim()) return
        viewModelScope.launch {
            try {
                repository.edit(chatId, target.id, text)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Правка не ушла: вернуть её в поле.
                draftBeforeEdit = _state.value.draft
                _state.update { it.copy(editing = target, draft = text) }
                show(e)
            }
        }
    }

    // Удаление

    /** «Удалить у всех» — только свои сообщения на сервере; в «Избранном» удаление одно. */
    fun canDeleteForEveryone(message: Message): Boolean =
        isOutgoing(message) && isServer(message) && chatId != Chat.SAVED_MESSAGES_ID

    val deletesWithoutChoice: Boolean get() = chatId == Chat.SAVED_MESSAGES_ID

    fun delete(message: Message, forEveryone: Boolean) {
        if (_state.value.replyTo?.id == message.id) cancelReply()
        if (!isServer(message)) {
            repository.discard(chatId, message.id)
            return
        }
        viewModelScope.launch {
            try {
                repository.delete(chatId, listOf(message.id), forEveryone || deletesWithoutChoice)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    // Реакции

    fun canReact(message: Message): Boolean = isServer(message) && !message.isService

    fun quickReactions(message: Message): List<String> =
        ReactionPalette.quick(_state.value.reactionCatalog, message.content.reactions.firstOrNull { it.mine }?.emoji)

    /** Поставить реакцию или снять свою. */
    fun toggleReaction(message: Message, emoji: String) {
        if (!canReact(message)) return
        val mine = message.content.reactions.firstOrNull { it.mine }?.emoji
        viewModelScope.launch {
            try {
                repository.react(chatId, message.id, if (mine == emoji) null else emoji)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(if (e is OrbitleError.Rejected) e else OrbitleError.Rejected(REACTION_FAILURE))
            }
        }
    }

    fun consumeMessage() {
        _messages.value = null
    }

    fun notify(text: String) {
        _messages.value = text
    }

    private fun isServer(message: Message) = message.status == MessageStatus.SENT && message.id.toLongOrNull() != null

    /** Прочитать всё до последнего чужого сообщения, пока экран виден. */
    private fun markRead() {
        if (!active) return
        val last = history.lastOrNull { isServer(it) } ?: return
        val unread = header?.chat?.unreadCount ?: 0
        if (last.id == markedReadId) return
        if (isOutgoing(last) && unread == 0) {
            markedReadId = last.id
            return
        }
        markedReadId = last.id
        viewModelScope.launch {
            try {
                repository.markRead(chatId, last.id)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Отметка прочтения не важна для экрана: повторится при следующем сообщении.
                markedReadId = null
            }
        }
    }

    private fun rebuildHeader() {
        val info = header
        if (info == null) {
            val title = fallbackTitle?.takeIf { it.isNotBlank() }
            val placeholder = title?.let {
                ChatHeaderUi(it, "", false, ChatAvatar(ChatAvatar.Kind.Initials(ChatAvatar.initials(it)), ChatAvatar.colorIndex(chatId)))
            }
            _state.update { it.copy(header = placeholder) }
            return
        }
        val chat = info.chat
        val title = ChatListFormatter().title(chat)
        val (subtitle, accent) = formatter.subtitle(info, now())
        _state.update {
            it.copy(
                header = ChatHeaderUi(title, subtitle, accent, ChatListFormatter().avatar(chat, title), chat.isVerified),
                canWrite = chat.canWrite != false,
            )
        }
        if (chat.unreadCount > 0) {
            markedReadId = null
            markRead()
        }
        if (chat.type != builtFor) rebuild()
    }

    private fun rebuild() {
        val nowMs = now()
        builtFor = header?.chat?.type
        val isGroup = builtFor == ChatType.GROUP
        val result = ArrayList<ChatItem>(history.size + 8)
        // Строится от старых к новым, потом разворачивается.
        var previous: Message? = null
        var previousDay: String? = null
        val ordered = history
        for ((index, message) in ordered.withIndex()) {
            val day = formatter.dayKey(message.timeMs)
            if (day != previousDay) {
                result += ChatItem.Day("day-$day", formatter.dayLabel(message.timeMs, nowMs))
                previousDay = day
                previous = null
            }
            if (message.isService) {
                result += ChatItem.Service(message.id, message.text)
                previous = null
                continue
            }
            val next = ordered.getOrNull(index + 1)
            val sameAsPrevious = previous != null && previous.authorId == message.authorId
            val sameAsNext = next != null && !next.isService && next.authorId == message.authorId &&
                formatter.dayKey(next.timeMs) == day
            val outgoing = isOutgoing(message)
            val author = if (isGroup && !outgoing && !sameAsPrevious) message.authorName.ifEmpty { null } else null
            val avatar = if (isGroup && !outgoing && !sameAsNext) {
                val name = message.authorName.ifEmpty { "?" }
                ChatAvatar(
                    message.authorAvatarUrl?.let { ChatAvatar.Kind.Photo(it, ChatAvatar.initials(name)) } ?: ChatAvatar.Kind.Initials(ChatAvatar.initials(name)),
                    ChatAvatar.colorIndex(message.authorId),
                )
            } else null
            result += ChatItem.Bubble(
                message = message,
                outgoing = outgoing,
                time = formatter.time(message.timeMs),
                authorName = author,
                authorColor = ChatAvatar.colorIndex(message.authorId),
                showsAvatar = avatar != null,
                avatar = avatar,
                continues = sameAsNext,
                isGroupChat = isGroup && !outgoing,
            )
            previous = message
        }
        result.reverse()
        val empty = latestLoaded && history.isEmpty()
        val hint = when {
            !empty -> null
            chatId == Chat.SAVED_MESSAGES_ID -> "Пересылайте сюда сообщения, сохраняйте заметки и файлы — их видите только вы."
            else -> "Здесь пока нет сообщений"
        }
        _state.update { it.copy(items = result, emptyHint = hint, isLoading = !latestLoaded && history.isEmpty()) }
    }

    override fun onCleared() {
        // Ушли из чата: его голосовое больше не играет.
        val playing = media.playback.value
        if (playing != null && history.any { it.id == playing.messageId }) media.stopVoice()
    }

    private fun show(error: Exception) {
        val text = (error as? OrbitleError)?.userMessage ?: OrbitleError.Unknown.userMessage
        if (text != null) _messages.value = text
    }

    companion object {
        const val REACTION_FAILURE = "Не удалось поставить реакцию"
    }
}

/** Быстрые реакции меню сообщения. */
object ReactionPalette {
    val FALLBACK = listOf("👍", "❤️", "🔥", "🤣", "😭", "😍")
    const val QUICK_COUNT = 6

    /** Начало каталога (или запасной набор); своя реакция вне ряда встаёт первой. */
    fun quick(catalog: List<String>, mine: String? = null): List<String> {
        val row = (catalog.ifEmpty { FALLBACK }).take(QUICK_COUNT).toMutableList()
        if (!mine.isNullOrEmpty() && mine !in row) {
            row.add(0, mine)
            if (row.size > QUICK_COUNT) row.removeAt(row.lastIndex)
        }
        return row
    }
}
