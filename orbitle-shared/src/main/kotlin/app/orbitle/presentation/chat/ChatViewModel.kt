package app.orbitle.presentation.chat

import app.orbitle.data.BotCommandRow
import app.orbitle.data.ChatMemberRow
import app.orbitle.data.ChatRepository
import app.orbitle.data.CommentsRepository
import app.orbitle.data.ComplaintChoice
import app.orbitle.data.SharedChat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.ChatHeaderInfo
import app.orbitle.data.LockPayloads
import app.orbitle.data.MessageRepository
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.OutgoingFile
import app.orbitle.domain.SavedMessagesWelcome
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.FoundMessage
import app.orbitle.domain.PinNotice
import app.orbitle.domain.Sticker
import app.orbitle.domain.TextSpan
import app.orbitle.data.RecentStickerStore
import app.orbitle.data.StickerRepository
import app.orbitle.presentation.stickers.AnimojiDraft
import app.orbitle.presentation.stickers.StickerPanel
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
        /** Следующее сообщение того же автора в пределах 15 минут: отдельный нижний угол не рисуется. */
        val continues: Boolean,
        val isGroupChat: Boolean,
        /** Плашка комментариев под постом канала: число, `null` — плашки нет. */
        val comments: Int? = null,
        /** Предыдущее сообщение того же автора в пределах 15 минут. Углы сверху не меняет. */
        val joinsPrevious: Boolean = false,
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
    /** Для общего заголовка приватного режима. */
    val type: app.orbitle.domain.ChatType = app.orbitle.domain.ChatType.PRIVATE,
    val isSavedMessages: Boolean = false,
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
    /** Закреплённое сообщение. Пусто, если закрепа нет. */
    val pinnedMessageId: String? = null,
    val pinnedText: String? = null,
    /** Подсказки `@` и `/` над полем ввода. */
    val hints: ComposerHints = ComposerHints(),
) {
    val canSend: Boolean get() = draft.isNotBlank() || attachments.isNotEmpty()
}

/** Люди для `@` и команды бота для `/`. */
data class ComposerHints(
    val mentions: List<ChatMemberRow> = emptyList(),
    val commands: List<BotCommandRow> = emptyList(),
)

/** Поиск внутри открытого чата. */
data class InChatSearchState(
    val query: String = "",
    val hits: List<FoundMessage> = emptyList(),
    val busy: Boolean = false,
    val error: String? = null,
)

/** Участники, общие чаты, жалобы и сигнал звонка. */
data class ChatToolsState(
    val members: List<ChatMemberRow> = emptyList(),
    val shared: List<SharedChat> = emptyList(),
    val reasons: List<ComplaintChoice> = emptyList(),
    val busy: Boolean = false,
    val notice: String? = null,
    val error: String? = null,
)

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
    stickerRepository: StickerRepository? = null,
    stickerRecents: RecentStickerStore? = null,
    /** Черновики полей ввода по чатам: переживают выход из чата и перезапуск. */
    private val drafts: DraftStore? = null,
    emojiSupported: (String) -> Boolean = { true },
    /** Комментарии постов канала; `null` — без них. */
    private val comments: CommentsRepository? = null,
    mediaSaver: MediaSaver? = null,
    private val chats: ChatRepository? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(ChatUiState())
    val state: StateFlow<ChatUiState> = _state.asStateFlow()

    private val _messages = MutableStateFlow<String?>(null)
    /** Ошибки и уведомления для снекбара. */
    val messages: StateFlow<String?> = _messages.asStateFlow()

    private val _search = MutableStateFlow(InChatSearchState())
    val search: StateFlow<InChatSearchState> = _search.asStateFlow()

    private val _tools = MutableStateFlow(ChatToolsState())
    val tools: StateFlow<ChatToolsState> = _tools.asStateFlow()

    private val _scheduled = MutableStateFlow<List<FoundMessage>>(emptyList())
    val scheduled: StateFlow<List<FoundMessage>> = _scheduled.asStateFlow()

    /** Голосовые, расшифровка, просмотр фото и видео, файлы. */
    val media = ChatMedia(chatId, repository, viewModelScope, voicePlayer, files, mediaSaver, onNotice = { _messages.value = it }, onError = { show(it) })

    /** Панель эмодзи и стикеров. */
    val stickers: StickerPanel? = stickerRecents?.let { StickerPanel(stickerRepository, it, viewModelScope, emojiSupported) }

    private var history: List<Message> = emptyList()
    private var header: ChatHeaderInfo? = null
    private var latestLoaded = false
    private var markedReadId: String? = null
    private var active = true
    private var draftBeforeEdit = ""
    private var builtFor: ChatType? = null
    private var builtComments: Boolean? = null
    /** Счётчики комментариев от сервера: id поста → число. */
    private val commentCounts = HashMap<String, Int>()
    private val askedCounts = HashSet<String>()
    /** Сообщения, для которых уже спрашивали реакции (`MSG_GET_REACTIONS`). */
    private val askedReactions = HashSet<String>()
    /** Анимодзи, вставленные в поле из панели. */
    private val animojiDraft = AnimojiDraft()
    private val mentionDraft = MentionDraft()
    /** Локальный закреп, пока в истории не появится более новое служебное pin/unpin. */
    private var pinOverride: PinNotice? = null
    /** Id сообщения истории, которое было последним pin-notice в момент локального pin/unpin. */
    private var pinBaselineId: String? = null
    private var memberRows: List<ChatMemberRow> = emptyList()
    private var commandRows: List<BotCommandRow> = emptyList()
    private var membersAsked = false
    private var commandsAsked = false

    private val _comments = MutableStateFlow<CommentsModel?>(null)
    /** Открытое обсуждение поста. */
    val commentsModel: StateFlow<CommentsModel?> = _comments.asStateFlow()

    init {
        drafts?.get(chatId)?.takeIf { it.isNotEmpty() }?.let { saved -> _state.update { it.copy(draft = saved) } }
        viewModelScope.launch {
            repository.messages(chatId).collect {
                history = it
                rebuild()
                markRead()
                requestReactions()
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

    fun setDraft(text: String) {
        if (text.isEmpty()) {
            animojiDraft.clear()
            mentionDraft.clear()
        } else {
            mentionDraft.retainPresent(text)
        }
        _state.update { it.copy(draft = text) }
        if (_state.value.editing == null) drafts?.put(chatId, text)
        refreshHints(text)
    }

    /** Вставить упоминание вместо хвоста `@запрос`. */
    fun insertMention(member: ChatMemberRow) {
        val draft = _state.value.draft
        val at = draft.lastIndexOf('@')
        if (at < 0) return
        val token = "@${member.name}"
        mentionDraft.insert(token, member.id)
        setDraft(draft.substring(0, at) + token + " ")
    }

    /** Подставить команду бота в поле. */
    fun insertCommand(command: BotCommandRow) {
        val name = command.name.trim().removePrefix("/")
        if (name.isEmpty()) return
        setDraft("/$name ")
    }

    /** Анимодзи из панели: символ вставляет экран, отметка уйдёт вместе с текстом. */
    fun noteAnimoji(emoji: AnimatedEmoji) {
        animojiDraft.insert(emoji)
    }

    /** Отправить стикер сразу, с текущим ответом. */
    /** Отправить записанное голосовое; ответ, если был, уходит с ним. */
    fun sendVoice(recording: app.orbitle.domain.VoiceRecording) {
        val reply = _state.value.replyTo
        _state.update { it.copy(replyTo = null) }
        viewModelScope.launch {
            try {
                repository.sendVoice(chatId, recording, reply?.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun sendSticker(sticker: Sticker) {
        val reply = _state.value.replyTo
        _state.update { it.copy(replyTo = null) }
        stickers?.usedSticker(sticker)
        viewModelScope.launch {
            try {
                repository.sendSticker(chatId, sticker, reply?.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

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
            animojiDraft.clear()
            mentionDraft.clear()
            sendAttachments(attachments, text)
            return
        }
        if (text.isEmpty()) return
        val marks = animojiDraft.spans(text) + mentionDraft.spans(text)
        animojiDraft.clear()
        mentionDraft.clear()
        _state.value.editing?.let { saveEdit(it, text); return }
        val reply = _state.value.replyTo
        _state.update { it.copy(draft = "", replyTo = null) }
        drafts?.put(chatId, "")
        viewModelScope.launch {
            try {
                if (marks.isEmpty()) repository.send(chatId, text, reply?.id)
                else repository.sendFormatted(chatId, text, reply?.id, marks)
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
        drafts?.put(chatId, "")
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

    /** Своё сообщение с вложениями, которое ещё грузится: загрузку можно отменить. */
    fun canCancelUpload(message: Message): Boolean =
        message.status == MessageStatus.SENDING && message.id.toLongOrNull() == null && message.content.attachments.isNotEmpty()

    /** Отменить загрузку [message] или, без него, все идущие загрузки чата. */
    fun cancelUpload(message: Message? = null) {
        val targets = message?.let { listOf(it) } ?: history.filter(::canCancelUpload)
        targets.filter(::canCancelUpload).forEach { repository.cancelUpload(chatId, it.id) }
        if (targets.isNotEmpty()) _state.update { it.copy(uploadProgress = null) }
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

    /** «Кто отреагировал» — в группах, у сообщений с реакциями. */
    fun canShowReactionUsers(message: Message): Boolean =
        builtFor == ChatType.GROUP && isServer(message) && message.content.reactions.isNotEmpty()

    fun reactionUsers(message: Message): ReactionUsersModel =
        ReactionUsersModel(chatId, message, repository, viewModelScope).also { it.load() }

    /** Пересылать можно только сообщения, уже лежащие на сервере. */
    fun canForward(message: Message): Boolean =
        isServer(message) && message.status == MessageStatus.SENT && !message.isService

    fun forward(message: Message, targetChatId: String) {
        if (!canForward(message)) return
        viewModelScope.launch {
            try {
                repository.forward(chatId, message.id, targetChatId)
                _messages.value = "Сообщение переслано"
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

    /**
     * Реакции показанных сообщений (`MSG_GET_REACTIONS`): в истории канала их нет,
     * а своя реакция с другого устройства приходит только в этом ответе.
     * Каждое сообщение спрашивается один раз за открытие чата. Ошибка снимает отметку,
     * и следующий приход истории спрашивает снова.
     */
    private fun requestReactions() {
        val ids = history.filter { isServer(it) && !it.isService && it.id !in askedReactions }.map { it.id }
        if (ids.isEmpty()) return
        askedReactions += ids
        viewModelScope.launch {
            try {
                repository.syncReactions(chatId, ids)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                askedReactions -= ids.toSet()
            }
        }
    }

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
                header = ChatHeaderUi(title, subtitle, accent, ChatListFormatter().avatar(chat, title), chat.isVerified, chat.type, chat.isSavedMessages),
                canWrite = chat.canWrite != false,
            )
        }
        if (chat.unreadCount > 0) {
            markedReadId = null
            markRead()
        }
        if (chat.type != builtFor || chat.commentsEnabled != builtComments) rebuild()
    }

    private fun rebuild() {
        val nowMs = now()
        builtFor = header?.chat?.type
        builtComments = header?.chat?.commentsEnabled
        val isGroup = builtFor == ChatType.GROUP
        requestCommentCounts()
        val result = feedItems(history, formatter, nowMs, isGroup, ::isOutgoing, ::commentsFooter, savedMessages = chatId == Chat.SAVED_MESSAGES_ID)
        // Скрытое приветствие «Избранного» не считается: без других сообщений видна подсказка.
        val empty = latestLoaded && result.isEmpty()
        val hint = when {
            !empty -> null
            chatId == Chat.SAVED_MESSAGES_ID -> "Пересылайте сюда сообщения, сохраняйте заметки и файлы — их видите только вы."
            else -> "Здесь пока нет сообщений"
        }
        val pinned = pinnedNow()
        _state.update {
            it.copy(
                items = result,
                emptyHint = hint,
                isLoading = !latestLoaded && history.isEmpty(),
                pinnedMessageId = pinned?.first,
                pinnedText = pinned?.second,
            )
        }
    }

    /** Последнее служебное pin/unpin в истории: id сообщения и само уведомление. */
    private fun latestPinAnchor(): Pair<String, PinNotice>? =
        history.asReversed().firstNotNullOfOrNull { message -> message.content.pin?.let { message.id to it } }

    private fun pinnedNow(): Pair<String, String>? {
        val latest = latestPinAnchor()
        if (pinOverride != null && latest?.first != pinBaselineId) {
            pinOverride = null
            pinBaselineId = null
        }
        val pin = pinOverride ?: latest?.second
        val id = pin?.messageId ?: return null
        return id to pin.preview.ifBlank { "Сообщение" }
    }

    fun canPin(message: Message): Boolean = isServer(message) && !message.isService

    fun pin(message: Message) {
        if (!canPin(message)) return
        viewModelScope.launch {
            try {
                repository.pin(chatId, message.id)
                pinBaselineId = latestPinAnchor()?.first
                pinOverride = PinNotice(message.id, message.replySnippet)
                rebuild()
                _messages.value = "Сообщение закреплено"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun unpin() {
        viewModelScope.launch {
            try {
                repository.pin(chatId, "0")
                pinBaselineId = latestPinAnchor()?.first
                pinOverride = PinNotice(null, "")
                rebuild()
                _messages.value = "Закреп снят"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun scheduleAt(text: String, sendAt: Long) {
        val body = text.trim()
        if (body.isEmpty()) {
            _messages.value = "Нечего откладывать"
            return
        }
        viewModelScope.launch {
            try {
                repository.schedule(chatId, body, sendAt)
                _messages.value = "Сообщение отложено"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun loadScheduled() {
        viewModelScope.launch {
            try {
                _scheduled.value = repository.scheduled(chatId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun sendPoll(title: String, answers: List<String>) {
        val clean = answers.map { it.trim() }.filter { it.isNotEmpty() }
        if (title.trim().isEmpty() || clean.size < 2) {
            _messages.value = "Нужны вопрос и два ответа"
            return
        }
        viewModelScope.launch {
            try {
                repository.sendPoll(chatId, title.trim(), clean)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun vote(message: Message, answerId: String) {
        val poll = message.content.poll ?: return
        if (!isServer(message)) return
        viewModelScope.launch {
            try {
                repository.votePoll(chatId, message.id, poll.id, answerId)
                repository.loadLatest(chatId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    fun searchInside(query: String) {
        val term = query.trim()
        if (term.isEmpty()) {
            _search.value = InChatSearchState()
            return
        }
        viewModelScope.launch {
            _search.update { it.copy(query = term, busy = true, error = null) }
            try {
                val hits = repository.searchInChat(chatId, term)
                if (_search.value.query != term) return@launch
                _search.update { it.copy(hits = hits, busy = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (_search.value.query != term) return@launch
                _search.update { it.copy(busy = false, hits = emptyList(), error = (e as? OrbitleError)?.userMessage ?: "Не удалось найти") }
            }
        }
    }

    /** Участники, общие чаты с собеседником и причины жалобы, если тип известен. */
    fun loadTools() {
        val source = chats ?: return
        viewModelScope.launch {
            _tools.update { it.copy(busy = true, error = null) }
            try {
                val chat = header?.chat
                val members = runCatching { source.members(chatId) }.getOrDefault(emptyList())
                val shared = chat?.peerId?.let { runCatching { source.commonChats(it) }.getOrDefault(emptyList()) }.orEmpty()
                val typeId = when (chat?.type) {
                    ChatType.CHANNEL -> LockPayloads.COMPLAINT_CHANNEL
                    ChatType.PRIVATE -> LockPayloads.COMPLAINT_USER
                    else -> null
                }
                val reasons = if (typeId == null) emptyList() else {
                    runCatching { source.complaintReasons()[typeId].orEmpty() }.getOrDefault(emptyList())
                }
                _tools.update { it.copy(members = members, shared = shared, reasons = reasons, busy = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _tools.update { it.copy(busy = false, error = (e as? OrbitleError)?.userMessage ?: "Не удалось открыть сведения чата") }
            }
        }
    }

    fun complain(reasonId: Int) {
        val source = chats ?: return
        val chat = header?.chat ?: return
        val (typeId, ids) = when (chat.type) {
            ChatType.CHANNEL -> LockPayloads.COMPLAINT_CHANNEL to listOf(chatId)
            ChatType.PRIVATE -> {
                val peer = chat.peerId ?: return
                LockPayloads.COMPLAINT_USER to listOf(peer)
            }
            else -> return
        }
        viewModelScope.launch {
            _tools.update { it.copy(busy = true, error = null, notice = null) }
            try {
                val ok = source.complain(reasonId, typeId, ids)
                _tools.update {
                    it.copy(busy = false, notice = if (ok) "Жалоба отправлена" else "Сервер не принял жалобу")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _tools.update { it.copy(busy = false, error = (e as? OrbitleError)?.userMessage ?: "Не удалось отправить жалобу") }
            }
        }
    }

    /** Удалить чат целиком. После успеха [onLeft] закрывает экран. */
    fun deleteChat(forEveryone: Boolean, onLeft: () -> Unit) {
        val source = chats ?: return
        viewModelScope.launch {
            _tools.update { it.copy(busy = true, error = null) }
            try {
                source.deleteChat(chatId, forEveryone)
                _tools.update { it.copy(busy = false) }
                onLeft()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _tools.update { it.copy(busy = false, error = (e as? OrbitleError)?.userMessage ?: "Не удалось удалить чат") }
            }
        }
    }

    /** Очистить переписку. Чат остаётся открытым. */
    fun clearHistory(forEveryone: Boolean) {
        val source = chats ?: return
        viewModelScope.launch {
            _tools.update { it.copy(busy = true, error = null, notice = null) }
            try {
                source.clearHistory(chatId, forEveryone)
                _tools.update { it.copy(busy = false, notice = "История очищена") }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _tools.update { it.copy(busy = false, error = (e as? OrbitleError)?.userMessage ?: "Не удалось очистить историю") }
            }
        }
    }

    /**
     * Просит сервер начать звонок. Звук и видео не передаются:
     * в [messages] остаётся честная фраза, если сервер принял сигнал.
     */
    fun signalCall(video: Boolean) {
        val source = chats ?: return
        val peer = header?.chat?.peerId ?: return
        if (header?.chat?.type != ChatType.PRIVATE) return
        viewModelScope.launch {
            _tools.update { it.copy(busy = true, error = null) }
            try {
                val call = source.signalCall(peer, video)
                _tools.update { it.copy(busy = false) }
                _messages.value = if (call == null) {
                    "Сервер не принял звонок"
                } else {
                    "Сервер принял звонок. Звук и видео этот клиент не передаёт."
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _tools.update { it.copy(busy = false, error = (e as? OrbitleError)?.userMessage ?: "Не удалось позвонить") }
            }
        }
    }

    private fun refreshHints(text: String) {
        val mention = mentionQuery(text)
        val command = commandQuery(text)
        val source = chats
        if (source != null && mention != null && !membersAsked) {
            membersAsked = true
            viewModelScope.launch {
                try {
                    memberRows = source.members(chatId)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    membersAsked = false
                }
                publishHints(_state.value.draft)
            }
        }
        val bot = header?.chat?.isBot == true
        val peer = header?.chat?.peerId
        if (source != null && command != null && bot && peer != null && !commandsAsked) {
            commandsAsked = true
            viewModelScope.launch {
                try {
                    commandRows = source.botCommands(peer)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    commandsAsked = false
                }
                publishHints(_state.value.draft)
            }
        }
        publishHints(text)
    }

    private fun publishHints(text: String) {
        val mention = mentionQuery(text)
        val command = commandQuery(text)
        val bot = header?.chat?.isBot == true
        val mentions = if (mention == null) emptyList() else memberRows.filter { it.name.contains(mention, ignoreCase = true) }.take(8)
        val commands = if (command == null || !bot) emptyList() else commandRows.filter {
            it.name.removePrefix("/").contains(command, ignoreCase = true)
        }.take(8)
        _state.update { it.copy(hints = ComposerHints(mentions, commands)) }
    }

    private fun mentionQuery(text: String): String? {
        val at = text.lastIndexOf('@')
        if (at < 0) return null
        val tail = text.substring(at + 1)
        if (tail.any { it.isWhitespace() }) return null
        return tail
    }

    private fun commandQuery(text: String): String? {
        if (!text.startsWith("/")) return null
        if (text.any { it.isWhitespace() }) return null
        return text.removePrefix("/")
    }

    // Комментарии

    /** Плашка под постом канала: только при включённых комментариях (или если сервер прислал счётчик). */
    private fun commentsFooter(message: Message): Int? {
        if (comments == null || builtFor != ChatType.CHANNEL || !isServer(message) || message.isService) return null
        val known = commentCounts[message.id]
        return when (builtComments) {
            false -> null
            true -> known ?: message.content.comments ?: 0
            null -> known ?: message.content.comments
        }
    }

    /** Спросить счётчики у постов, которых ещё не спрашивали (пачками по 50). */
    private fun requestCommentCounts() {
        val source = comments ?: return
        if (builtFor != ChatType.CHANNEL || builtComments == false) return
        val ids = history.filter { isServer(it) && !it.isService && it.id !in askedCounts }.map { it.id }
        if (ids.isEmpty()) return
        askedCounts += ids
        viewModelScope.launch {
            for (chunk in ids.chunked(50)) {
                val counts = try {
                    source.counts(chatId, chunk)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // Спросить ещё раз, когда лента обновится: иначе плашка так и не появится.
                    askedCounts -= chunk.toSet()
                    continue
                }
                if (counts.isEmpty()) continue
                commentCounts.putAll(counts)
                rebuild()
            }
        }
    }

    fun openComments(post: Message) {
        val source = comments ?: return
        if (_comments.value?.post?.id == post.id) return
        val model = CommentsModel(chatId, post, repository.currentUserId.orEmpty(), source, viewModelScope, formatter, now)
        _comments.value = model
        model.load()
    }

    /** Окно закрыто: счётчик поста мог измениться, спросить заново. */
    fun closeComments() {
        val post = _comments.value?.post ?: return
        _comments.value = null
        askedCounts -= post.id
        requestCommentCounts()
    }

    /** Число комментариев поста: ответ сервера, иначе счётчик из самого сообщения. */
    fun commentCount(post: Message): Int? = commentCounts[post.id] ?: post.content.comments

    override fun onCleared() {
        // Ушли из чата: его голосовое больше не играет.
        val playing = media.playback.value
        if (playing != null && history.any { it.id == playing.messageId }) media.stopVoice()
    }

    private fun show(error: Exception) {
        val text = app.orbitle.data.CoreErrors.map(error).userMessage
        if (text != null) _messages.value = text
    }

    companion object {
        const val REACTION_FAILURE = "Не удалось поставить реакцию"
    }
}

/**
 * Строки ленты от новых к старым: дни, служебные строки и пузыри. Общая для чата и комментариев.
 * [comments] — плашка комментариев под постом (`null` — без неё).
 * В «Избранном» ([savedMessages]) служебное приветствие-ключ сервера не показывается.
 */
internal fun feedItems(
    history: List<Message>,
    formatter: ChatFormatter,
    nowMs: Long,
    isGroup: Boolean,
    isOutgoing: (Message) -> Boolean,
    comments: (Message) -> Int? = { null },
    savedMessages: Boolean = false,
): List<ChatItem> {
    val result = ArrayList<ChatItem>(history.size + 8)
    // Строится от старых к новым, потом разворачивается.
    var previous: Message? = null
    var previousDay: String? = null
    val ordered = if (savedMessages) history.filterNot { SavedMessagesWelcome.isKey(it.text) } else history
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
        val sameAsPrevious = previous != null && messagesAttach(
            message.authorId, message.timeMs, previous.authorId, previous.timeMs, sameDay = true,
        )
        val sameAsNext = next != null && !next.isService && messagesAttach(
            message.authorId, message.timeMs, next.authorId, next.timeMs, formatter.dayKey(next.timeMs) == day,
        )
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
            comments = comments(message),
            joinsPrevious = sameAsPrevious,
        )
        previous = message
    }
    result.reverse()
    return result
}

/** Черновики полей ввода: id чата → текст. */
interface DraftStore {
    fun get(chatId: String): String?
    fun put(chatId: String, text: String)
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
