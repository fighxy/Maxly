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
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.DeletePlan
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
import app.orbitle.domain.TypingKind
import app.orbitle.data.RecentStickerStore
import app.orbitle.data.StickerRepository
import app.orbitle.presentation.stickers.AnimojiDraft
import app.orbitle.presentation.stickers.StickerPanel
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.chatlist.ChatListFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/** Строка ленты. Лента идёт от новых к старым: экран рисует её перевёрнутой. */
sealed interface ChatItem {
    val key: String

    data class Day(override val key: String, val label: String) : ChatItem

    /** «Непрочитанные сообщения» над первым непрочитанным при открытии чата. */
    data object Unread : ChatItem {
        override val key: String get() = "unread"
    }

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
        /** День сообщения («Сегодня», «12 марта»): плавающая дата над лентой при прокрутке. */
        val day: String = "",
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
    /** Собеседник личного чата: владелец кольца историй на аватаре. */
    val peerId: String? = null,
    /** Чей аватар с кольцом: человек, группа или канал. Пусто — кольца нет. */
    val storyOwnerId: String? = null,
    val storyOwnerType: app.orbitle.domain.StoryOwner.Type = app.orbitle.domain.StoryOwner.Type.USER,
)

data class ChatUiState(
    val header: ChatHeaderUi? = null,
    val items: List<ChatItem> = emptyList(),
    val draft: String = "",
    val replyTo: Message? = null,
    val editing: Message? = null,
    val canWrite: Boolean = true,
    /** Бот с мини-приложением: над полем ввода «Открыть приложение». */
    val botAppId: String? = null,
    /** Канал или группа вне списка: «Подписаться» или «Вступить» вместо плашки. */
    val join: JoinUi? = null,
    /**
     * Писать нельзя, а чат в списке (подписан на канал): вместо поля ввода кнопка звука.
     * `true` — уведомления выключены. `null` — кнопки нет.
     */
    val muted: Boolean? = null,
    val isLoading: Boolean = true,
    val isLoadingOlder: Boolean = false,
    val hasOlder: Boolean = true,
    /** Лента в окне перехода: ниже есть ещё не загруженные сообщения, до свежих. */
    val hasNewer: Boolean = false,
    val isLoadingNewer: Boolean = false,
    /** Переход к далёкому сообщению: его окно грузится. */
    val isJumping: Boolean = false,
    /** Кнопка «вниз» сначала вернёт к сообщению, с которого перешли. */
    val canReturn: Boolean = false,
    /** Куда прокрутить ленту; экран выполняет и снимает ([ChatViewModel.consumeScroll]). */
    val scroll: ScrollRequest? = null,
    /** Пустой загруженный чат: подсказка вместо ленты. */
    val emptyHint: String? = null,
    val quickReactions: List<String> = ReactionPalette.FALLBACK,
    val reactionCatalog: List<String> = emptyList(),
    /** Чужих сообщений ниже экрана: число на кнопке «вниз». */
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
    /** Разметка текста поля ввода ([FormatDraft]): поле рисует её и отправляет с текстом. */
    val formatting: List<TextSpan> = emptyList(),
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
    /** Черновики на сервере; `null` — только на устройстве. */
    private val draftSync: DraftSync? = null,
    emojiSupported: (String) -> Boolean = { true },
    /** Комментарии постов канала; `null` — без них. */
    private val comments: CommentsRepository? = null,
    mediaSaver: MediaSaver? = null,
    private val chats: ChatRepository? = null,
    /** Карточка канала или группы, которых нет в сторе (открыты из поиска): шапка и «Подписаться». */
    private val profiles: app.orbitle.data.ProfileRepository? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(ChatUiState())
    val state: StateFlow<ChatUiState> = _state.asStateFlow()

    private val _messages = MutableStateFlow<String?>(null)
    /** Ошибки и уведомления для снекбара. */
    val messages: StateFlow<String?> = _messages.asStateFlow()

    private val _search = MutableStateFlow(InChatSearchState())
    val search: StateFlow<InChatSearchState> = _search.asStateFlow()

    private val _tools = MutableStateFlow(ChatToolsState())
    /** Участники группы или канала в «О чате»: постранично и с поиском. */
    val memberList: app.orbitle.presentation.profile.MemberList? = chats?.let { app.orbitle.presentation.profile.MemberList(viewModelScope, it, chatId) }

    /** Подпись присутствия участника в «О чате» («в сети», «был(а)…»); `null` — ничего не известно. */
    fun memberPresence(person: app.orbitle.data.ChatPerson): String? = formatter.presence(person.isOnline, person.lastSeenMs, now(), person.presence)
    val tools: StateFlow<ChatToolsState> = _tools.asStateFlow()

    private val _scheduled = MutableStateFlow<List<FoundMessage>>(emptyList())
    val scheduled: StateFlow<List<FoundMessage>> = _scheduled.asStateFlow()

    /** Голосовые, расшифровка, просмотр фото и видео, файлы. */
    val media = ChatMedia(chatId, repository, viewModelScope, voicePlayer, files, mediaSaver, onNotice = { _messages.value = it }, onError = { show(it) })

    /** «Печатает…», запись и загрузка для собеседников: правила в [TypingSendPolicy]. */
    private val typingPolicy = TypingSendPolicy()
    private var recordingWatch: Job? = null
    private var recordingTicks: Job? = null

    /** Панель эмодзи и стикеров. */
    val stickers: StickerPanel? = stickerRecents?.let {
        StickerPanel(stickerRepository, it, viewModelScope, emojiSupported, onStickers = { sendTyping(typingPolicy.openStickers(chatId, now(), canWrite = canSignalTyping())) })
    }

    private var history: List<Message> = emptyList()
    /** Что из [history] видит лента: живая лента или окно перехода ([jumpTime]). */
    private var visible: List<Message> = emptyList()
    private var header: ChatHeaderInfo? = null
    private var latestLoaded = false
    /** Непрерывные куски истории чата: переживают экран. */
    private val ranges = HistoryRanges.of(chatId)
    /** Окно перехода: момент сообщения, к которому перешли; `null` — живая лента. */
    private var jumpTime: Long? = null
    /** Откуда переходили (ответ → оригинал): кнопка «вниз» возвращает туда по очереди. */
    private val returnStack = ArrayDeque<String>()
    private var scrollToken = 0
    /**
     * Лента у низа и следует за новыми: читается всё. Пока экран не сообщил, где лента, чат с
     * непрочитанными не следует (откроется на первом непрочитанном).
     */
    private var following = true
    /** Самое новое сообщение, которое было на экране (мс): до него чат прочитан. */
    private var seenMs = 0L
    /** Своя отметка прочтения из шапки при открытии. */
    private var readMarkMs = 0L
    /** Окно вокруг первого непрочитанного уже спрашивали. */
    private var unreadFetched = false
    /** Прежнее место в ленте уже проверяли. */
    private var placeChecked = false
    /**
     * Свежая страница не пришла, а ленты нет: вместо «Здесь пока нет сообщений» — почему пусто.
     * Снимается удачной загрузкой.
     */
    private var latestFailure: String? = null
    /** Над этим сообщением «Непрочитанные сообщения»: ставится один раз при открытии. */
    private var unreadAnchorId: String? = null
    /** Непрочитанные при открытии, ещё не нашедшие места в ленте; `-1` — шапки ещё не было. */
    private var pendingUnread = -1
    /** Сообщение, до которого отметка уже ушла (или не нужна: последнее — своё). */
    private var markedReadId: String? = null
    /** Время (мс) сообщения [markedReadId]: отметка старше неё не уходит. */
    private var sentReadMs = 0L
    /** Отложенная отметка: пока она ждёт, более новая заменяет её, а уход с экрана отменяет. */
    private var readJob: Job? = null
    /** Сообщение, до которого читает [readJob]. */
    private var pendingRead: Message? = null
    /** Счётчик непрочитанных из прошлой шапки: отметка повторяется, только когда он вырос. */
    private var headerUnread = 0
    private var active = true
    /** Чат только что помечен непрочитанным и закрывается: прочтение не отправляется. */
    private var markingUnread = false
    private var draftBeforeEdit = ""
    private var builtFor: ChatType? = null
    private var builtComments: Boolean? = null
    /** Счётчики комментариев от сервера: id поста → число. */
    private val commentCounts = HashMap<String, Int>()
    private val askedCounts = HashSet<String>()
    /** Сообщения, для которых уже спрашивали реакции (`MSG_GET_REACTIONS`). */
    private val askedReactions = HashSet<String>()
    /** После ошибки реакции и счётчики не спрашиваются до этого времени: иначе каждое обновление ленты
     *  повторяло бы запрос, и сервер отвечал бы too.many.requests всему, включая комментарии. */
    private var reactionsRetryAt = 0L
    private var countsRetryAt = 0L
    /** Идущий запрос счётчиков: следующий уходит только после него. */
    private var countsJob: Job? = null
    /** Отложенный повтор счётчиков после отказа: один на чат. */
    private var countsRetry: Job? = null
    /** Отказов подряд при запросе счётчиков: после [COUNTS_RETRIES] сами больше не повторяем. */
    private var countsFailures = 0
    /** Последний известный флаг комментариев канала: неполная карточка чата без `options` его не сбрасывает. */
    private var knownComments: Boolean? = null
    /** Анимодзи, вставленные в поле из панели. */
    private val animojiDraft = AnimojiDraft()
    private val mentionDraft = MentionDraft()
    /** Жирный, курсив и прочая разметка поля ввода. */
    private val formatDraft = FormatDraft()
    /** Разметка черновика до начала правки: вернётся вместе с его текстом. */
    private var formatsBeforeEdit: List<TextSpan> = emptyList()
    /** Упоминания черновика до начала правки. */
    private var mentionsBeforeEdit: List<TextSpan> = emptyList()
    /** Локальный закреп, пока в истории не появится более новое служебное pin/unpin. */
    private var pinOverride: PinNotice? = null
    /** Id сообщения истории, которое было последним pin-notice в момент локального pin/unpin. */
    private var pinBaselineId: String? = null
    private var memberRows: List<ChatMemberRow> = emptyList()
    private var commandRows: List<BotCommandRow> = emptyList()
    private var membersAsked = false
    private var commandsAsked = false

    private val _selection = MutableStateFlow<Set<String>>(emptySet())
    /**
     * Выбранные сообщения (id). Пустой набор — режима выбора нет: он начинается с первого
     * выбранного и кончается, когда снят последний.
     */
    val selection: StateFlow<Set<String>> = _selection.asStateFlow()

    private val _comments = MutableStateFlow<CommentsModel?>(null)
    /** Открытое обсуждение поста. */
    val commentsModel: StateFlow<CommentsModel?> = _comments.asStateFlow()

    // Черновик: поля объявлены до init, который восстанавливает черновик.

    /** Время восстановленного черновика: более ранний с сервера его не заменит. */
    private var restoredDraftAt = 0L
    /** Поле меняли после открытия чата. */
    private var draftTouched = false
    /** Ответ из черновика, пока сообщения нет в загруженной ленте. */
    private var draftReplyId: String? = null

    init {
        restoreDraft()
        draftSync?.let { sync ->
            viewModelScope.launch {
                // Черновик с другого устройства или его стирание пришли позже открытия, а поле ещё не трогали.
                sync.serverDrafts.drafts.collect {
                    if (draftTouched || _state.value.editing != null) return@collect
                    val shown = currentDraft()?.copy(updatedAtMs = restoredDraftAt)
                    val next = sync.reconcile(chatId, shown)
                    when {
                        next == null -> if (shown != null) clearRestoredDraft()
                        next === shown || next.sameContent(shown) -> Unit
                        else -> applyDraft(next)
                    }
                }
            }
        }
        viewModelScope.launch {
            repository.messages(chatId).collect {
                history = it
                attachDraftReply()
                pruneSelection()
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
                repository.openLatestPage(chatId)?.let(ranges::addLatest)
                latestLoaded = true
                latestFailure = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (app.orbitle.data.CoreErrors.map(e).isRateLimit) {
                    // Сервер просит подождать. Лента из стора остаётся, пустой экран объясняет
                    // паузу; сверка повторится сама. Снекбар не нужен: он закрыл бы низ экрана.
                    latestFailure = RATE_LIMIT_HINT
                    scheduleLatestRetry()
                } else {
                    latestFailure = (e as? OrbitleError)?.userMessage ?: "Не удалось загрузить сообщения"
                    show(e)
                }
            }
            _state.update { it.copy(isLoading = false) }
            rebuild()
        }
    }

    private var latestRetry: kotlinx.coroutines.Job? = null

    /**
     * Повтор свежей страницы после `too.many.requests`, тихо: ошибки уже показаны или не нужны.
     * Не больше [LATEST_RETRY_LIMIT] раз, с растущей паузой: каждый отказ продлевает ограничение
     * сервера, и бесконечный повтор в чате, который сервер не отдаёт, держал бы под ним весь
     * аккаунт.
     */
    private fun scheduleLatestRetry(attempt: Int = 0) {
        latestRetry?.cancel()
        if (attempt >= LATEST_RETRY_LIMIT) return
        latestRetry = viewModelScope.launch {
            delay(RATE_LIMIT_RETRY_MS shl attempt)
            try {
                repository.loadLatest(chatId)
                latestLoaded = true
                latestFailure = null
                rebuild()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!app.orbitle.data.CoreErrors.map(e).isRateLimit) return@launch
                if (attempt + 1 < LATEST_RETRY_LIMIT) {
                    scheduleLatestRetry(attempt + 1)
                } else if (latestFailure != null) {
                    // Сам больше не спрашиваем: пустой экран говорит, что делать.
                    latestFailure = RATE_LIMIT_GAVE_UP_HINT
                    rebuild()
                }
            }
        }
    }

    /** До этого времени старые страницы не спрашиваются: прокрутка у верха после ошибки
     *  иначе повторяла бы запрос на каждое изменение ленты. */
    private var olderRetryAt = 0L
    /** Отказы подряд при подгрузке старого: после паузы страница спрашивается снова сама, но
     *  не больше [OLDER_AUTO_RETRIES] раз — дальше ждёт прокрутки. */
    private var olderFailures = 0
    private var olderRetry: Job? = null

    fun loadOlder() {
        val current = _state.value
        if (current.isLoadingOlder || !current.hasOlder || !latestLoaded || history.isEmpty()) return
        if (now() < olderRetryAt) return
        val oldest = visible.firstOrNull { it.status == MessageStatus.SENT } ?: history.firstOrNull() ?: return
        _state.update { it.copy(isLoadingOlder = true) }
        viewModelScope.launch {
            val more = try {
                val span = repository.olderPage(chatId, oldest.timeMs)
                if (span != null && span.count > 0) ranges.add(span.oldestMs, oldest.timeMs)
                if (span?.reachedOldest == true) ranges.markBeginning(if (span.count > 0) span.oldestMs else oldest.timeMs)
                rebuild()
                span?.reachedOldest != true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val limited = app.orbitle.data.CoreErrors.map(e).isRateLimit
                val wait = if (limited) {
                    (app.orbitle.data.ServerRateLimit.shared.remainingMs() ?: OLDER_RETRY_MS).coerceIn(OLDER_RETRY_MS, RATE_LIMIT_RETRY_MS)
                } else {
                    OLDER_RETRY_MS
                }
                olderRetryAt = now() + wait
                if (!limited) show(e)
                // Читатель у верха ждёт страницу: после паузы она спрашивается снова сама.
                if (++olderFailures <= OLDER_AUTO_RETRIES) {
                    olderRetry?.cancel()
                    olderRetry = viewModelScope.launch {
                        delay(wait)
                        olderRetryAt = 0L
                        loadOlder()
                    }
                }
                null
            }
            if (more != null) olderFailures = 0
            _state.update { it.copy(isLoadingOlder = false, hasOlder = more ?: it.hasOlder) }
        }
    }

    /** Окно перехода дошло до низа экрана: следующая страница к свежим. */
    fun loadNewer() {
        val target = jumpTime ?: return
        if (_state.value.isLoadingNewer) return
        val newest = visible.lastOrNull { it.status == MessageStatus.SENT } ?: return
        _state.update { it.copy(isLoadingNewer = true) }
        viewModelScope.launch {
            try {
                val span = repository.newerPage(chatId, newest.timeMs)
                if (span != null) ranges.add(newest.timeMs, if (span.reachedNewest) Long.MAX_VALUE else span.newestMs)
                // Окно догнало живую ленту: дальше это просто лента.
                if (span == null || ranges.around(target) == ranges.live()) jumpTime = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!app.orbitle.data.CoreErrors.map(e).isRateLimit) show(e)
            }
            _state.update { it.copy(isLoadingNewer = false) }
            rebuild()
        }
    }

    /**
     * Переход к сообщению (цитата ответа, закреп, поиск): посередине экрана с подсветкой. Не в
     * ленте — грузится окно вокруг него. [from] — сообщение, с которого перешли: кнопка «вниз»
     * вернёт к нему.
     */
    /**
     * Чат открыт на сообщении (найденном в общем поиске): лента встаёт на нём, как после перехода
     * по цитате, а не на «Непрочитанных» или прежнем месте. [atMs] — время сообщения, если известно.
     */
    fun openAt(messageId: String, atMs: Long = 0) {
        openedAtMessage = true
        placeChecked = true
        jumpTo(messageId, atMs = atMs)
    }

    /** Чат открыли на сообщении ([openAt]): «Непрочитанные» не уводят ленту от него. */
    private var openedAtMessage = false

    fun jumpTo(messageId: String, from: String? = null, atMs: Long = 0) {
        if (from != null && from != messageId && returnStack.lastOrNull() != from) returnStack.addLast(from)
        if (visible.any { it.id == messageId }) {
            following = false
            requestScroll(ScrollRequest.Target.Message(messageId, highlight = true))
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isJumping = true) }
            try {
                val time = history.firstOrNull { it.id == messageId }?.timeMs
                    ?: atMs.takeIf { it > 0 }
                    ?: repository.findMessage(chatId, messageId)?.timeMs
                if (time == null) {
                    _messages.value = "Сообщение не найдено"
                    if (from != null) returnStack.remove(from)
                    return@launch
                }
                if (history.none { it.id == messageId } || ranges.around(time) == null) {
                    val span = repository.pageAround(chatId, time)
                    if (span == null) {
                        _messages.value = "Сообщение не загрузилось"
                        if (from != null) returnStack.remove(from)
                        return@launch
                    }
                    addAround(span)
                }
                jumpTime = if (ranges.live()?.contains(time) == true) null else time
                following = false
                rebuild()
                requestScroll(ScrollRequest.Target.Message(messageId, highlight = true))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (from != null) returnStack.remove(from)
                show(e)
            } finally {
                _state.update { it.copy(isJumping = false) }
            }
        }
    }

    /** Кнопка «вниз»: сначала назад к сообщению, с которого переходили, потом к свежим. */
    fun scrollDown() {
        while (returnStack.isNotEmpty()) {
            val back = returnStack.removeLast()
            if (history.any { it.id == back }) {
                val time = history.first { it.id == back }.timeMs
                if (visible.none { it.id == back }) {
                    jumpTime = if (ranges.live()?.contains(time) != false) null else time
                    rebuild()
                }
                publishReturn()
                requestScroll(ScrollRequest.Target.Message(back, highlight = false))
                return
            }
        }
        if (jumpTime != null) {
            jumpTime = null
            rebuild()
        }
        following = true
        publishReturn()
        requestScroll(ScrollRequest.Target.Bottom)
        markRead()
    }

    /**
     * Что на экране: [newestKey] — самая новая видимая строка, [atBottom] — лента у низа и
     * следует за новыми. Чат читается до самого нового увиденного сообщения.
     */
    fun onVisible(newestKey: String?, atBottom: Boolean) {
        following = atBottom && jumpTime == null
        val seen = newestKey?.let { key -> visible.firstOrNull { it.id == key }?.timeMs }
        if (seen != null && seen > seenMs) seenMs = seen
        if (following) visible.lastOrNull()?.timeMs?.let { if (it > seenMs) seenMs = it }
        publishUnreadBelow()
        markRead()
    }

    /** Экран уходит: где была лента ([place]); у низа — `null`, чат откроется на свежих. */
    fun savePlace(place: ScrollPlace?) {
        ScrollMemory.put(chatId, if (jumpTime == null) place else null)
    }

    /** Экран выполнил запрос прокрутки [token]. */
    fun consumeScroll(token: Int) {
        if (_state.value.scroll?.token == token) _state.update { it.copy(scroll = null) }
    }

    private fun requestScroll(target: ScrollRequest.Target) {
        scrollToken++
        _state.update { it.copy(scroll = ScrollRequest(target, scrollToken)) }
    }

    private fun publishReturn() {
        _state.update { it.copy(canReturn = returnStack.isNotEmpty(), hasNewer = jumpTime != null) }
    }

    private fun publishUnreadBelow() {
        val below = when {
            following -> 0
            // Экран ещё не сообщил, что видно: счётчик сервера.
            seenMs == 0L -> header?.chat?.unreadCount ?: 0
            else -> {
                val loaded = history.count { it.timeMs > seenMs && isServer(it) && !isOutgoing(it) && !it.isService }
                // В окне перехода ниже есть и не загруженные: счётчик сервера, он падает по мере прочтения.
                if (jumpTime != null) maxOf(loaded, header?.chat?.unreadCount ?: 0) else loaded
            }
        }
        if (below != _state.value.unreadBelow) _state.update { it.copy(unreadBelow = below) }
    }

    private fun addAround(span: app.orbitle.data.HistorySpan) {
        ranges.add(span.oldestMs, if (span.reachedNewest) Long.MAX_VALUE else span.newestMs)
        if (span.reachedOldest) ranges.markBeginning(span.oldestMs)
    }

    /**
     * Первое непрочитанное раньше загруженного: окно вокруг своей отметки прочтения, лента
     * откроется на нём и дальше догрузится к свежим.
     */
    private fun fetchUnread() {
        // Открыли на найденном сообщении: окно вокруг отметки прочтения увело бы ленту от него.
        if (unreadFetched || openedAtMessage) return
        unreadFetched = true
        viewModelScope.launch {
            try {
                val span = repository.pageAround(chatId, readMarkMs)
                if (span != null) {
                    addAround(span)
                    jumpTime = if (ranges.live()?.contains(readMarkMs) == true) null else readMarkMs
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Без окна разделитель встанет у самого старого из загруженных.
            }
            // Больше не ищем: лучшее, что есть, — самое старое загруженное чужое.
            rebuild(unreadSettled = true)
        }
    }

    /** Своё сообщение уходит: лента возвращается к свежим и встаёт вниз. */
    private fun toLatest() {
        returnStack.clear()
        placeChecked = true
        if (jumpTime != null) {
            jumpTime = null
            rebuild()
        }
        following = true
        publishReturn()
        requestScroll(ScrollRequest.Target.Bottom)
    }

    /**
     * Экран виден: можно отмечать прочитанным. Уход с экрана (приложение свернули, окно потеряло
     * фокус или свернулось) отменяет ещё не ушедшую отметку: невидимое не читается.
     */
    fun setActive(value: Boolean) {
        active = value
        if (value) {
            markingUnread = false
            markRead()
        } else {
            cancelPendingRead()
        }
    }

    /**
     * Текст поля ввода. [cursor] — курсор после правки (`-1` — неизвестен): по нему разметка
     * точнее находит место правки среди одинаковых знаков.
     */
    fun setDraft(text: String, cursor: Int = -1) {
        val previous = _state.value.draft
        val typed = text.isNotEmpty() && text != previous && _state.value.editing == null
        if (text.isEmpty()) {
            animojiDraft.clear()
            mentionDraft.clear()
            formatDraft.clear()
        } else {
            mentionDraft.retainPresent(text)
            formatDraft.edit(previous, text, cursor)
        }
        _state.update { it.copy(draft = text, formatting = formatDraft.spans) }
        if (_state.value.editing == null) syncDraft()
        refreshHints(text)
        if (typed) sendTyping(typingPolicy.editText(chatId, now(), canWrite = canSignalTyping()))
    }

    /** Собеседникам видно, что пользователь что-то делает: в личке и группе, не в канале и не в «Избранном». */
    private fun canSignalTyping(): Boolean {
        val chat = header?.chat ?: return false
        return chat.type != ChatType.CHANNEL && !chat.isSavedMessages && _state.value.canWrite
    }

    private fun sendTyping(frame: TypingSendPolicy.Frame?) {
        frame ?: return
        viewModelScope.launch {
            try {
                repository.sendTyping(frame.chatId, frame.kind, frame.postId)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Сигнал необязателен: следующий уйдёт с очередным действием.
            }
        }
    }

    /** Запись голосового или кружка из поля ввода: пока она идёт, собеседники видят «записывает…». */
    fun watchRecording(recording: StateFlow<RecordingController.State>) {
        recordingWatch?.cancel()
        recordingWatch = viewModelScope.launch {
            try {
                recording.map { if (it.isActive) it.recording else null }.distinctUntilChanged().collect { mode ->
                    stopRecordingTyping()
                    if (mode == null) return@collect
                    val kind = if (mode == RecordingMode.VIDEO) TypingKind.VIDEO_MSG else TypingKind.AUDIO
                    val canWrite = canSignalTyping()
                    sendTyping(typingPolicy.startRecording(chatId, kind, now(), canWrite = canWrite))
                    if (canWrite) recordingTicks = viewModelScope.launch {
                        while (true) {
                            val next = typingPolicy.nextTickAt() ?: break
                            delay((next - now()).coerceAtLeast(0))
                            typingPolicy.tick(now()).forEach(::sendTyping)
                        }
                    }
                }
            } finally {
                stopRecordingTyping()
            }
        }
    }

    private fun stopRecordingTyping() {
        typingPolicy.stopRecording(chatId)
        recordingTicks?.cancel()
        recordingTicks = null
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

    // Форматирование

    /**
     * Кнопка панели форматирования (или сочетание клавиш) для выделения [start, end) поля:
     * размеченное целиком — снять, иначе разметить. Ссылки — [setLink].
     */
    fun toggleFormat(kind: TextSpan.Kind, start: Int, end: Int) {
        if (kind !in FormatDraft.TOOLBAR || kind == TextSpan.Kind.LINK) return
        val (from, to) = clampSelection(start, end) ?: return
        formatDraft.toggle(kind, from, to)
        publishFormatting()
    }

    /**
     * Ссылка на выделении [start, end): [url] из диалога (без схемы — `https://`), `null` или
     * пусто — убрать ссылку. Адрес с пробелами не принимается.
     */
    fun setLink(start: Int, end: Int, url: String?) {
        val (from, to) = clampSelection(start, end) ?: return
        if (url.isNullOrBlank()) {
            formatDraft.setLink(from, to, null)
        } else {
            val normalized = FormatDraft.normalizeUrl(url)
            if (normalized == null) {
                _messages.value = "Ссылка не похожа на адрес"
                return
            }
            formatDraft.setLink(from, to, normalized)
        }
        publishFormatting()
    }

    /** Адрес ссылки на выделении, чтобы диалог открылся с ним. */
    fun linkAt(start: Int, end: Int): String? = clampSelection(start, end)?.let { (from, to) -> formatDraft.linkAt(from, to) }

    private fun clampSelection(start: Int, end: Int): Pair<Int, Int>? {
        val length = _state.value.draft.length
        val from = minOf(start, end).coerceIn(0, length)
        val to = maxOf(start, end).coerceIn(0, length)
        return if (to > from) from to to else null
    }

    private fun publishFormatting() {
        _state.update { it.copy(formatting = formatDraft.spans) }
        if (_state.value.editing == null) syncDraft()
    }

    // Черновик

    /** Поле ввода как черновик: текст, все отметки и ответ. Ответ без текста — тоже черновик; `null` — ни того, ни другого. */
    private fun currentDraft(): ChatDraft? {
        val reply = _state.value.replyTo?.id ?: draftReplyId
        val text = _state.value.draft
        if (text.isBlank()) return reply?.let { ChatDraft("", now(), emptyList(), it) }
        val marks = (animojiDraft.spans(text) + mentionDraft.spans(text) + formatDraft.spans)
            .distinctBy { Triple(it.kind, it.from, it.length) }
            .sortedWith(app.orbitle.domain.TextSpans.ORDER)
        return ChatDraft(text, now(), marks, reply)
    }

    /** Поле поменялось: сразу на устройство, на сервер — после паузы. */
    private fun syncDraft() {
        draftTouched = true
        val draft = currentDraft()
        drafts?.save(chatId, draft)
        draftSync?.changed(chatId, draft)
    }

    /**
     * Черновик при открытии: устройства или сервера ([DraftSync.reconcile], правило ядра). Если
     * черновик устройства проиграл стиранию на другом устройстве, он удаляется и здесь.
     */
    private fun restoreDraft() {
        val local = drafts?.load(chatId)?.takeUnless { it.isEmpty }
        val sync = draftSync
        val shown = if (sync == null) local else sync.reconcile(chatId, local)
        if (shown == null) {
            if (local != null) drafts?.save(chatId, null)
            return
        }
        applyDraft(shown)
    }

    /** Черновик в поле стёрли на другом устройстве, а здесь его ещё не трогали: поле пустеет. */
    private fun clearRestoredDraft() {
        animojiDraft.clear()
        mentionDraft.clear()
        formatDraft.clear()
        draftReplyId = null
        restoredDraftAt = 0L
        drafts?.save(chatId, null)
        _state.update { it.copy(draft = "", formatting = formatDraft.spans, replyTo = null) }
    }

    /** Сообщение ушло: черновика больше нет ни здесь, ни на сервере. */
    private fun dropDraft() {
        draftTouched = true
        draftReplyId = null
        drafts?.save(chatId, null)
        draftSync?.sent(chatId)
    }

    /** Черновик в поле: текст, разметка, «живые» упоминания и анимодзи, ответ. */
    private fun applyDraft(draft: ChatDraft) {
        val text = draft.text
        val spans = draft.formatting.filter { it.from >= 0 && it.length > 0 && it.from + it.length <= text.length }
        formatDraft.restore(spans, text.length)
        restoreMentions(text, spans)
        animojiDraft.clear()
        for (span in spans) {
            if (span.kind != TextSpan.Kind.ANIMOJI) continue
            val id = span.entityId ?: continue
            animojiDraft.insert(AnimatedEmoji(id, text.substring(span.from, span.from + span.length), lottieUrl = span.url))
        }
        restoredDraftAt = draft.updatedAtMs
        draftReplyId = draft.replyTo
        _state.update { it.copy(draft = text, formatting = formatDraft.spans, replyTo = null) }
        attachDraftReply()
    }

    /** Ответ черновика показывается, как только его сообщение есть в ленте. */
    private fun attachDraftReply() {
        val id = draftReplyId ?: return
        if (_state.value.editing != null || _state.value.replyTo != null) return
        val message = history.firstOrNull { it.id == id } ?: return
        draftReplyId = null
        _state.update { it.copy(replyTo = message) }
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
        draftReplyId = null
        syncDraft()
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

    fun sendVideoNote(recording: app.orbitle.domain.VideoNoteRecording) {
        val reply = _state.value.replyTo
        _state.update { it.copy(replyTo = null) }
        draftReplyId = null
        syncDraft()
        viewModelScope.launch {
            try {
                repository.sendVideoNote(chatId, recording, reply?.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    /** Готовая запись из поля ввода: голосовое или кружок. */
    fun sendRecorded(draft: RecordedDraft) = when (draft) {
        is RecordedDraft.Voice -> sendVoice(draft.recording)
        is RecordedDraft.Note -> sendVideoNote(draft.recording)
    }

    fun sendSticker(sticker: Sticker) {
        val reply = _state.value.replyTo
        _state.update { it.copy(replyTo = null) }
        draftReplyId = null
        syncDraft()
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

    /** Сохраняет позицию вложения и подпись при выходе из редактора. */
    fun replaceAttachment(original: OutgoingFile, edited: OutgoingFile) = _state.update {
        it.copy(attachments = it.attachments.map { item -> if (item.path == original.path) edited else item })
    }

    fun send() {
        val text = _state.value.draft.trim()
        val attachments = _state.value.attachments
        if (_state.value.editing == null && (text.isNotEmpty() || attachments.isNotEmpty())) toLatest()
        if (attachments.isNotEmpty() && _state.value.editing == null) {
            animojiDraft.clear()
            mentionDraft.clear()
            formatDraft.clear()
            dropUnreadSeparator()
            sendAttachments(attachments, text)
            return
        }
        if (text.isEmpty()) return
        val marks = composedMarks(text)
        animojiDraft.clear()
        mentionDraft.clear()
        formatDraft.clear()
        _state.value.editing?.let { saveEdit(it, text, marks); return }
        dropUnreadSeparator()
        val reply = _state.value.replyTo
        _state.update { it.copy(draft = "", replyTo = null, formatting = emptyList()) }
        dropDraft()
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

    /**
     * Отметки текста [text] (уже без пробелов по краям): анимодзи, упоминания и разметка поля.
     * Одинаковая отметка из двух черновиков (анимодзи правимого сообщения) уходит один раз.
     */
    private fun composedMarks(text: String): List<TextSpan> {
        val formats = formatDraft.trimmed(_state.value.draft).second
        return (animojiDraft.spans(text) + mentionDraft.spans(text) + formats)
            .distinctBy { Triple(it.kind, it.from, it.length) }
            .sortedWith(app.orbitle.domain.TextSpans.ORDER)
    }

    private fun sendAttachments(items: List<OutgoingFile>, caption: String) {
        val reply = _state.value.replyTo
        _state.update { it.copy(draft = "", replyTo = null, attachments = emptyList(), uploadProgress = 0f, formatting = emptyList()) }
        dropDraft()
        val uploadKind = uploadKind(items)
        val canSignal = canSignalTyping()
        val signalUpload = { sendTyping(typingPolicy.uploadProgress(chatId, uploadKind, now(), canWrite = canSignal)) }
        signalUpload()
        viewModelScope.launch {
            try {
                repository.sendMedia(chatId, items, caption, reply?.id) { fraction ->
                    signalUpload()
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

    private fun uploadKind(items: List<OutgoingFile>): TypingKind = when {
        items.any { it.kind == OutgoingFile.Kind.FILE } -> TypingKind.FILE
        items.any { it.kind == OutgoingFile.Kind.VIDEO } -> TypingKind.VIDEO
        else -> TypingKind.PHOTO
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

    /** «Сведения» — у любого сообщения на сервере, кроме служебных ([MessageInfoModel.isOffered]). */
    fun canShowInfo(message: Message): Boolean = MessageInfoModel.isOffered(message)

    fun messageInfo(message: Message): MessageInfoModel =
        MessageInfoModel(chatId, message, builtFor, message.authorId == repository.currentUserId, repository, viewModelScope)
            .also { it.load() }

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
        draftReplyId = null
        syncDraft()
    }

    fun cancelReply() {
        _state.update { it.copy(replyTo = null) }
        draftReplyId = null
        syncDraft()
    }

    /**
     * Ответ на сообщение выше ([older]) или ниже выбранного, по Ctrl+↑ / Ctrl+↓
     * на десктопе: без ответа — на последнее сообщение, у последнего вниз — ответ снимается. Лента
     * показывает выбранное. `false` — выбирать не из чего.
     */
    fun replyToNeighbour(older: Boolean): Boolean {
        val candidates = visible.filter { it.status == MessageStatus.SENT && !it.isService && it.id.toLongOrNull() != null }
        if (candidates.isEmpty()) return false
        val current = _state.value.replyTo?.let { reply -> candidates.indexOfFirst { it.id == reply.id } } ?: -1
        val next = when {
            current < 0 -> if (older) candidates.lastIndex else return false
            older -> (current - 1).coerceAtLeast(0)
            current == candidates.lastIndex -> {
                cancelReply()
                return true
            }
            else -> current + 1
        }
        val message = candidates[next]
        beginReply(message)
        requestScroll(ScrollRequest.Target.Message(message.id, highlight = true))
        return true
    }

    // Правка

    fun canEdit(message: Message): Boolean =
        isOutgoing(message) && isServer(message) && message.content.forward == null && message.text.isNotBlank() && !message.isService

    /** Правка: в поле текст сообщения с его разметкой и упоминаниями. */
    fun beginEdit(message: Message) {
        if (!canEdit(message)) return
        if (_state.value.editing == null) {
            draftBeforeEdit = _state.value.draft
            formatsBeforeEdit = formatDraft.spans
            mentionsBeforeEdit = mentionDraft.spans(draftBeforeEdit)
        }
        val text = message.text
        val spans = message.content.formatting
        formatDraft.restore(spans, text.length)
        restoreMentions(text, spans)
        _state.update { it.copy(editing = message, replyTo = null, draft = text, formatting = formatDraft.spans) }
    }

    /** Упоминания из разметки [spans] текста [text] — снова «живые» в поле ввода. */
    private fun restoreMentions(text: String, spans: List<TextSpan>) {
        mentionDraft.clear()
        for (span in spans) {
            if (span.kind != TextSpan.Kind.MENTION) continue
            val userId = span.userId ?: continue
            if (span.from < 0 || span.from + span.length > text.length) continue
            mentionDraft.insert(text.substring(span.from, span.from + span.length), userId)
        }
    }

    /** ↑ в пустом поле ввода: правка своего последнего сообщения, которое можно править. */
    fun editLast(): Boolean {
        val last = visible.lastOrNull { canEdit(it) } ?: return false
        beginEdit(last)
        return true
    }

    /** К последнему сообщению (Ctrl+End): окно перехода и возвраты больше не нужны. */
    fun toBottom() = toLatest()

    fun cancelEdit() {
        if (_state.value.editing == null) return
        formatDraft.restore(formatsBeforeEdit, draftBeforeEdit.length)
        restoreMentions(draftBeforeEdit, mentionsBeforeEdit)
        _state.update { it.copy(editing = null, draft = draftBeforeEdit, formatting = formatDraft.spans) }
        draftBeforeEdit = ""
        formatsBeforeEdit = emptyList()
        mentionsBeforeEdit = emptyList()
    }

    private fun saveEdit(target: Message, text: String, marks: List<TextSpan>) {
        val restore = draftBeforeEdit
        val restoreFormats = formatsBeforeEdit
        val restoreMentionSpans = mentionsBeforeEdit
        draftBeforeEdit = ""
        formatsBeforeEdit = emptyList()
        mentionsBeforeEdit = emptyList()
        formatDraft.restore(restoreFormats, restore.length)
        restoreMentions(restore, restoreMentionSpans)
        _state.update { it.copy(editing = null, draft = restore, formatting = formatDraft.spans) }
        if (app.orbitle.domain.TextSpans.unchanged(target.text, target.content.formatting, text, marks)) return
        viewModelScope.launch {
            try {
                repository.editFormatted(chatId, target.id, text, marks)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Правка не ушла: вернуть её в поле вместе с разметкой.
                draftBeforeEdit = _state.value.draft
                formatsBeforeEdit = formatDraft.spans
                mentionsBeforeEdit = mentionDraft.spans(draftBeforeEdit)
                formatDraft.restore(marks, text.length)
                restoreMentions(text, marks)
                _state.update { it.copy(editing = target, draft = text, formatting = formatDraft.spans) }
                show(e)
            }
        }
    }

    // Удаление

    /** «Удалить у всех» — только свои сообщения на сервере; в «Избранном» удаление одно. */
    fun canDeleteForEveryone(message: Message): Boolean = deletePlan(listOf(message)).showsForEveryone

    val deletesWithoutChoice: Boolean get() = chatId == Chat.SAVED_MESSAGES_ID

    /**
     * Как можно удалить [messages] — план ядра ([MessageRepository.deletePlan]): вид чата, мои
     * права в нём и `edit-timeout` сервера.
     */
    fun deletePlan(messages: List<Message>): DeletePlan = repository.deletePlan(chatId, messages)

    /** [messages] можно удалить хоть как-то (в канале без прав — нельзя). */
    fun canDelete(messages: List<Message>): Boolean = deletePlan(messages).canDelete

    /** [messages] удаляются только у всех, без выбора (канал с правами). */
    fun deletesOnlyForEveryone(messages: List<Message>): Boolean = deletePlan(messages).forcesForEveryone

    fun delete(message: Message, forEveryone: Boolean) = delete(listOf(message), forEveryone)

    /**
     * Удалить несколько сообщений: не ушедшие убираются из ленты, остальные — одним запросом.
     * «У всех» — только если так можно удалить каждое ([deletePlan]); в канале с правами — всегда.
     */
    fun delete(messages: List<Message>, forEveryone: Boolean) {
        if (messages.isEmpty()) return
        val plan = deletePlan(messages)
        if (!plan.canDelete) return
        val everyone = (forEveryone && plan.showsForEveryone) || plan.forcesForEveryone || deletesWithoutChoice
        if (messages.any { it.id == _state.value.replyTo?.id }) cancelReply()
        val (server, local) = messages.partition(::isServer)
        local.forEach { repository.discard(chatId, it.id) }
        if (server.isEmpty()) return
        viewModelScope.launch {
            try {
                val outcome = repository.deleteMessages(chatId, server.map { it.id }, everyone)
                // Оставленные сервером сообщения остаются в ленте: сказать, сколько их.
                if (outcome.failed.isNotEmpty()) _messages.value = MessageSelection.deleteFailedNotice(outcome.failed.size, server.size)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    // Выбор нескольких сообщений

    /** Выбрать можно сообщение, уже лежащее на сервере, кроме служебного. */
    fun canSelect(message: Message): Boolean = isServer(message) && !message.isService

    val isSelecting: Boolean get() = _selection.value.isNotEmpty()

    /** «Выбрать» в меню сообщения: режим выбора начинается с [message]. */
    fun startSelection(message: Message) {
        if (!canSelect(message)) return
        _selection.update { it + message.id }
    }

    /** Нажатие на сообщение в режиме выбора (или Ctrl+щелчок на десктопе). */
    fun toggleSelection(message: Message) {
        if (!canSelect(message)) return
        _selection.update { if (message.id in it) it - message.id else it + message.id }
    }

    fun clearSelection() {
        _selection.value = emptySet()
    }

    /** Выбранные сообщения от старых к новым. */
    fun selectedMessages(): List<Message> {
        val ids = _selection.value
        if (ids.isEmpty()) return emptyList()
        return history.filter { it.id in ids }.sortedWith(MessageSelection.chronological)
    }

    /** Текст выбранного для буфера обмена ([MessageSelection.copyText]). */
    fun selectionText(): String = MessageSelection.copyText(selectedMessages(), formatter.zone, ::authorLabel)

    /** «У всех» — только если так можно удалить каждое выбранное ([deletePlan]). */
    fun canDeleteSelectionForEveryone(): Boolean = canDeleteForEveryone(selectedMessages())

    fun canDeleteForEveryone(messages: List<Message>): Boolean = deletePlan(messages).showsForEveryone

    /** Удалить выбранное одним запросом и выйти из режима выбора. */
    fun deleteSelection(forEveryone: Boolean) {
        val targets = selectedMessages()
        clearSelection()
        delete(targets, forEveryone)
    }

    /** Переслать выбранное в [targetChatId] и выйти из режима выбора ([forwardSelection]). */
    fun forwardSelection(targetChatId: String) = forwardSelection(listOf(targetChatId), null)

    /**
     * Переслать выбранное в чаты [targetChatIds] и выйти из режима выбора. Порядок —
     * [MessageSelection.forwardPlan]: комментарий в каждый чат, затем сообщения от старых к новым,
     * каждое во все чаты. Подряд идущие сообщения в один чат уходят одним
     * [MessageRepository.forwardMessages]; ошибка останавливает остальные.
     */
    fun forwardSelection(targetChatIds: List<String>, comment: String?) {
        val targets = selectedMessages().filter(::canForward)
        clearSelection()
        val plan = MessageSelection.forwardPlan(targets, targetChatIds, comment)
        val total = plan.count { it is MessageSelection.ForwardStep.Forward }
        if (total == 0) return
        viewModelScope.launch {
            try {
                var sent = 0
                var error: Throwable? = null
                for (batch in forwardBatches(plan)) {
                    val first = batch.first()
                    if (first is MessageSelection.ForwardStep.Comment) {
                        try {
                            repository.send(first.target, first.text, null)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            error = e
                            break
                        }
                        continue
                    }
                    val ids = batch.map { (it as MessageSelection.ForwardStep.Forward).messageId }
                    val outcome = repository.forwardMessages(chatId, ids, first.target)
                    sent += outcome.sent
                    if (outcome.error != null) {
                        error = outcome.error
                        break
                    }
                }
                if (error == null) {
                    _messages.value = MessageSelection.forwardedNotice(sent)
                    return@launch
                }
                val reason = app.orbitle.data.CoreErrors.map(error).userMessage
                // Часть уже ушла: сказать сколько, иначе показалось бы, что не ушло ничего.
                _messages.value = if (sent == 0) reason ?: return@launch
                else listOfNotNull("Переслано $sent из $total", reason).joinToString(". ")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            }
        }
    }

    /** Шаги пересылки по запросам: комментарий — один, подряд идущие сообщения в один чат — вместе. */
    private fun forwardBatches(plan: List<MessageSelection.ForwardStep>): List<List<MessageSelection.ForwardStep>> {
        val batches = ArrayList<MutableList<MessageSelection.ForwardStep>>()
        for (step in plan) {
            val last = batches.lastOrNull()
            val joins = step is MessageSelection.ForwardStep.Forward && last != null &&
                last.first() is MessageSelection.ForwardStep.Forward && last.first().target == step.target
            if (joins) last!!.add(step) else batches.add(mutableListOf(step))
        }
        return batches
    }

    /** Имя автора в скопированной переписке. */
    private fun authorLabel(message: Message): String {
        message.authorName.takeIf { it.isNotBlank() }?.let { return it }
        if (isOutgoing(message)) return "Вы"
        val chat = header?.chat
        if (chat != null && chat.type == ChatType.PRIVATE && !chat.isSavedMessages) return ChatListFormatter().title(chat)
        return MessageSelection.NO_NAME
    }

    /** Выбранные сообщения пропали из ленты (удалены, в том числе на другом устройстве): снять выбор. */
    private fun pruneSelection() {
        val ids = _selection.value
        if (ids.isEmpty()) return
        val present = history.filter { it.id in ids && canSelect(it) }.mapTo(HashSet()) { it.id }
        if (present.size != ids.size) _selection.value = ids intersect present
    }

    // Реакции

    /**
     * Реакции показанных сообщений (`MSG_GET_REACTIONS`): в истории канала их нет,
     * а своя реакция с другого устройства приходит только в этом ответе.
     * Каждое сообщение спрашивается один раз за открытие чата. Ошибка снимает отметку,
     * и следующий приход истории спрашивает снова.
     */
    private fun requestReactions() {
        if (now() < reactionsRetryAt) return
        // Самые новые первыми и не больше одной пачки за раз: остальные спросит следующее обновление.
        val ids = history.filter { isServer(it) && !it.isService && it.id !in askedReactions }.map { it.id }.takeLast(REACTIONS_BATCH)
        if (ids.isEmpty()) return
        askedReactions += ids
        viewModelScope.launch {
            try {
                repository.syncReactions(chatId, ids)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                askedReactions -= ids.toSet()
                reactionsRetryAt = now() + RETRY_AFTER_ERROR_MS
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

    private val _openUrl = MutableStateFlow<String?>(null)
    /** Адрес, который экран должен открыть: ответ бота на кнопку или кнопка-ссылка. */
    val openUrl: StateFlow<String?> = _openUrl.asStateFlow()

    private val _botApp = MutableStateFlow<BotAppRequest?>(null)
    /** Мини-приложение бота, которое экран должен открыть. */
    val botApp: StateFlow<BotAppRequest?> = _botApp.asStateFlow()

    fun consumeOpenUrl() {
        _openUrl.value = null
    }

    fun consumeBotApp() {
        _botApp.value = null
    }

    /** «Открыть приложение» в чате с ботом. */
    fun openBotApp() {
        val bot = _state.value.botAppId ?: return
        _botApp.value = BotAppRequest(bot, chatId, null, _state.value.header?.title ?: "Приложение")
    }

    /**
     * Нажатие inline-кнопки бота. Ссылка — открыть, копирование экран делает сам, `OPEN_APP` —
     * мини-приложение, остальное уходит боту (опкод 118): текст ответа — снекбар, адрес — открыть.
     */
    fun pressButton(message: Message, button: app.orbitle.domain.InlineButton) {
        when (val action = button.action) {
            is app.orbitle.domain.InlineButton.Action.Link -> _openUrl.value = action.url
            is app.orbitle.domain.InlineButton.Action.Copy -> Unit
            is app.orbitle.domain.InlineButton.Action.OpenApp -> {
                val bot = action.botId ?: _state.value.botAppId ?: header?.chat?.takeIf { it.isBot }?.let { peerOf(it) }
                if (bot == null) {
                    _messages.value = "Не удалось открыть приложение"
                    return
                }
                _botApp.value = BotAppRequest(bot, action.chatId ?: chatId, action.startParam, button.text)
            }
            app.orbitle.domain.InlineButton.Action.Callback -> {
                val callbackId = message.content.keyboard?.callbackId
                val repo = chats
                if (callbackId.isNullOrEmpty() || repo == null || !isServer(message)) {
                    _messages.value = "Кнопка не поддерживается"
                    return
                }
                viewModelScope.launch {
                    try {
                        val answer = repo.pressButton(chatId, message.id, callbackId, button.payload)
                        answer.url?.let { _openUrl.value = it }
                        answer.text?.let { _messages.value = it }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        show(e)
                    }
                }
            }
        }
    }

    /** Собеседник диалога: id чата диалога — это id пользователей через xor. */
    private fun peerOf(chat: Chat): String? {
        val me = repository.currentUserId?.toLongOrNull() ?: return null
        val id = chat.id.toLongOrNull() ?: return null
        return (id xor me).takeIf { it != 0L && it != me }?.toString()
    }

    private fun isServer(message: Message) = message.status == MessageStatus.SENT && message.id.toLongOrNull() != null

    /**
     * Прочитать всё до последнего увиденного сообщения, пока экран виден. Уходит только самая новая
     * отметка и только через [ReadMarkRules.DEBOUNCE_MS] после её последней смены: пока отправка
     * ждёт, более новый кандидат заменяет прежний, а отметка не новее уже отправленной не уходит.
     */
    private fun markRead() {
        if (!active || markingUnread) return
        val last = (if (following) history.lastOrNull { isServer(it) } else visible.lastOrNull { isServer(it) && it.timeMs <= seenMs }) ?: return
        // Только новее уже отправленной. Шапка с выросшим счётчиком снимает лишь [markedReadId]:
        // та же отметка может уйти снова, более старая — никогда.
        if (last.timeMs < sentReadMs || markedReadId != null && !newerThan(last, sentReadMs, markedReadId)) return
        // Ждёт тот же или более новый кандидат: таймер не перезапускается.
        pendingRead?.let { if (!newerThan(last, it.timeMs, it.id)) return }
        val unread = header?.chat?.unreadCount ?: 0
        if (isOutgoing(last) && unread == 0) {
            // Последнее — своё и непрочитанных нет: сервер уже считает чат прочитанным.
            cancelPendingRead()
            markedReadId = last.id
            sentReadMs = last.timeMs
            return
        }
        readJob?.cancel()
        pendingRead = last
        readJob = viewModelScope.launch {
            delay(ReadMarkRules.DEBOUNCE_MS)
            // Пауза прошла: дальше отправка не отменяется ни новым кандидатом, ни уходом с экрана.
            readJob = null
            pendingRead = null
            val previousId = markedReadId
            val previousMs = sentReadMs
            markedReadId = last.id
            sentReadMs = last.timeMs
            sendRead(last, previousId, previousMs)
        }
    }

    private suspend fun sendRead(message: Message, previousId: String?, previousMs: Long) {
        try {
            repository.markRead(chatId, message.id)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Отметка не важна для экрана: не ушла — повторится при следующем обновлении.
            if (markedReadId == message.id) {
                markedReadId = previousId
                sentReadMs = previousMs
            }
        }
    }

    /**
     * [message] новее сообщения [id] со временем [timeMs]. При равном времени решает id сервера:
     * он растёт с каждым сообщением.
     */
    private fun newerThan(message: Message, timeMs: Long, id: String?): Boolean {
        if (message.timeMs != timeMs) return message.timeMs > timeMs
        val mine = message.id.toLongOrNull() ?: return false
        val other = id?.toLongOrNull() ?: return true
        return mine > other
    }

    /** Снять ещё не ушедшую отметку. */
    private fun cancelPendingRead() {
        readJob?.cancel()
        readJob = null
        pendingRead = null
    }

    /** Карточка чата, которого нет в сторе: канал или группа из поиска. */
    private var outsider: app.orbitle.domain.ChatProfile? = null
    private var outsiderAsked = false
    private var joining = false

    /** Чата нет в сторе: спросить карточку один раз, чтобы показать название и «Подписаться». */
    private fun askOutsider() {
        val repo = profiles ?: return
        if (outsiderAsked || chatId == Chat.SAVED_MESSAGES_ID) return
        outsiderAsked = true
        viewModelScope.launch {
            try {
                val card = repo.profile(chatId)
                if (card.kind == app.orbitle.domain.ChatProfile.Kind.CHANNEL || card.kind == app.orbitle.domain.ChatProfile.Kind.GROUP) {
                    outsider = card
                    rebuildHeader()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Без карточки остаётся название из поиска.
            }
        }
    }

    /**
     * «Подписаться» в канале или «Вступить» в группе вне списка: вступление по публичной ссылке
     * (`CHAT_JOIN`). Чат встаёт в стор, и шапка с полем ввода переходят на него сами.
     */
    fun join() {
        val link = outsider?.link ?: return
        val repo = chats ?: return
        if (joining) return
        joining = true
        rebuildHeader()
        viewModelScope.launch {
            try {
                repo.joinByLink(link)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
            } finally {
                joining = false
                rebuildHeader()
            }
        }
    }

    private fun rebuildHeader() {
        val stored = header
        val card = outsider
        // Чата нет в сторе, но карточка пришла: шапка из неё, писать нельзя до вступления.
        val info = stored ?: card?.let {
            ChatHeaderInfo(
                Chat(
                    id = chatId,
                    title = it.title.ifBlank { fallbackTitle.orEmpty() },
                    type = if (it.kind == app.orbitle.domain.ChatProfile.Kind.CHANNEL) ChatType.CHANNEL else ChatType.GROUP,
                    updatedAtMs = 0,
                    avatarUrl = it.avatarUrl,
                    isVerified = it.isOfficial,
                    commentsEnabled = it.commentsEnabled,
                    canWrite = false,
                ),
                participants = it.participants,
            )
        }
        val join = if (stored == null && card != null && card.link != null) {
            JoinUi(if (card.kind == app.orbitle.domain.ChatProfile.Kind.CHANNEL) "Подписаться" else "Вступить", joining)
        } else null
        // Сервер принял звук: своё нажатие больше не нужно держать поверх стора.
        if (stored != null && pendingMute == stored.chat.isMuted) pendingMute = null
        if (info == null) {
            askOutsider()
            val title = fallbackTitle?.takeIf { it.isNotBlank() }
            val placeholder = title?.let {
                ChatHeaderUi(it, "", false, ChatAvatar(ChatAvatar.Kind.Initials(ChatAvatar.initials(it)), ChatAvatar.colorIndex(chatId)))
            }
            // Чата нет в сторе: канал или группа из поиска, по ссылке из поста. Писать туда нельзя,
            // пока не подписался; новый диалог из контактов встаёт в стор заготовкой и сюда не попадает.
            _state.update { it.copy(header = placeholder, canWrite = chatId == Chat.SAVED_MESSAGES_ID) }
            return
        }
        val chat = info.chat
        val title = ChatListFormatter().title(chat)
        val (subtitle, accent) = formatter.subtitle(info, now())
        // Непрочитанные при открытии — из первой шапки, до отметки прочтения.
        if (pendingUnread < 0) {
            pendingUnread = chat.unreadCount
            readMarkMs = info.readMarkMs
            // Чат с непрочитанными откроется на первом из них: читать будем то, что увидят.
            if (pendingUnread > 0) following = false
            placeUnreadAnchor()
        }
        _state.update {
            it.copy(
                header = ChatHeaderUi(
                    title, subtitle, accent, ChatListFormatter().avatar(chat, title), chat.isVerified, chat.type, chat.isSavedMessages,
                    peerId = chat.peerId.takeIf { chat.type == app.orbitle.domain.ChatType.PRIVATE && !chat.isSavedMessages && it != "0" },
                    storyOwnerId = when {
                        chat.isSavedMessages -> null
                        chat.type == app.orbitle.domain.ChatType.PRIVATE -> chat.peerId?.takeIf { it != "0" }
                        else -> chat.id
                    },
                    storyOwnerType = when (chat.type) {
                        app.orbitle.domain.ChatType.GROUP -> app.orbitle.domain.StoryOwner.Type.CHAT
                        app.orbitle.domain.ChatType.CHANNEL -> app.orbitle.domain.StoryOwner.Type.CHANNEL
                        else -> app.orbitle.domain.StoryOwner.Type.USER
                    },
                ),
                canWrite = chat.canWrite != false,
                botAppId = info.botAppId,
                join = join,
                muted = if (stored != null && chats != null && chat.canWrite == false) pendingMute ?: chat.isMuted else null,
            )
        }
        schedulePresenceTick(info)
        // Непрочитанных стало больше (пришли с синхронизацией, мимо ленты): прочитать заново то,
        // что на экране. Пока счётчик не растёт, шапка отметку не повторяет: она обновляется
        // каждую секунду, а часть чата может законно оставаться непрочитанной.
        val grew = chat.unreadCount > headerUnread
        headerUnread = chat.unreadCount
        if (grew) {
            markedReadId = null
            markRead()
        }
        chat.commentsEnabled?.let { knownComments = it }
        if (chat.type == ChatType.CHANNEL && stored != null && commentsFlag() == null) askCommentsFlag()
        if (chat.type != builtFor || commentsFlag() != builtComments) rebuild()
    }

    private var commentsFlagAsked = false

    /** Пересборка шапки, когда «был(а) 5 минут назад» должно смениться само. */
    private var presenceTick: Job? = null

    private fun schedulePresenceTick(info: ChatHeaderInfo) {
        presenceTick?.cancel()
        val at = now()
        val next = formatter.subtitleChange(info, at) ?: return
        presenceTick = viewModelScope.launch {
            delay((next - at).coerceAtLeast(0) + 1)
            // Часы стоят (тесты): пересчитывать нечего.
            if (now() != at) rebuildHeader()
        }
    }

    /** Нажатый звук, пока стор его не отразил: кнопка меняется сразу. */
    private var pendingMute: Boolean? = null

    /** Кнопка звука вместо поля ввода (канал, где писать нельзя): выключить или включить уведомления. */
    fun toggleMute() {
        val chats = chats ?: return
        val next = !(_state.value.muted ?: return)
        pendingMute = next
        _state.update { it.copy(muted = next) }
        viewModelScope.launch {
            try {
                chats.setMuted(chatId, next)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                pendingMute = null
                _state.update { it.copy(muted = header?.chat?.isMuted ?: it.muted?.not()) }
                show(e)
            }
        }
    }

    /**
     * Канал из списка, а опции `COMMENTS` в его строке нет: список отдаёт чаты коротко. Флаг —
     * из полной карточки канала, один раз, как на iOS. Без него родные комментарии не видны.
     */
    private fun askCommentsFlag() {
        val repo = profiles ?: return
        if (commentsFlagAsked) return
        commentsFlagAsked = true
        viewModelScope.launch {
            try {
                val flag = repo.profile(chatId).commentsEnabled ?: return@launch
                knownComments = flag
                rebuild()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Без карточки флаг остаётся неизвестным: плашки нет, как при выключенных.
            }
        }
    }

    private fun commentsFlag(): Boolean? = header?.chat?.commentsEnabled ?: knownComments

    /** Ответил — значит, прочитал: разделитель непрочитанных больше не нужен. */
    private fun dropUnreadSeparator() {
        pendingUnread = 0
        if (unreadAnchorId == null) return
        unreadAnchorId = null
        rebuild()
    }

    private fun placeUnreadAnchor() {
        if (pendingUnread <= 0 || unreadAnchorId != null) return
        rebuild()
    }

    private fun rebuild(unreadSettled: Boolean = false) {
        val nowMs = now()
        builtFor = header?.chat?.type
        builtComments = commentsFlag()
        val isGroup = builtFor == ChatType.GROUP
        visible = TimelineFilter.visible(history, ranges, jumpTime)
        requestCommentCounts()
        if (pendingUnread > 0 && unreadAnchorId == null) placeUnread(unreadSettled)
        if (!placeChecked && pendingUnread == 0 && unreadAnchorId == null && visible.isNotEmpty() && latestLoaded) {
            placeChecked = true
            ScrollMemory.get(chatId)?.takeIf { place -> visible.any { it.id == place.key } }?.let {
                following = false
                requestScroll(ScrollRequest.Target.Place(it))
            }
        }
        val result = feedItems(
            visible, formatter, nowMs, isGroup, ::isOutgoing, ::commentsFooter,
            savedMessages = chatId == Chat.SAVED_MESSAGES_ID, unreadAnchorId = unreadAnchorId,
        )
        // Скрытое приветствие «Избранного» не считается: без других сообщений видна подсказка.
        val failure = latestFailure
        val empty = (latestLoaded || failure != null) && result.isEmpty()
        val hint = when {
            !empty -> null
            failure != null -> failure
            chatId == Chat.SAVED_MESSAGES_ID -> "Пересылайте сюда сообщения, сохраняйте заметки и файлы — их видите только вы."
            else -> "Здесь пока нет сообщений"
        }
        val pinned = pinnedNow()
        val range = if (jumpTime != null) jumpTime?.let(ranges::around) else ranges.live()
        _state.update {
            it.copy(
                items = result,
                emptyHint = hint,
                isLoading = !latestLoaded && history.isEmpty(),
                pinnedMessageId = pinned?.first,
                pinnedText = pinned?.second,
                hasNewer = jumpTime != null,
                canReturn = returnStack.isNotEmpty(),
                hasOlder = if (range != null && ranges.startsAtBeginning(range)) false else it.hasOlder,
            )
        }
        publishUnreadBelow()
    }

    /**
     * Где встаёт «Непрочитанные сообщения»: над первым чужим новее своей отметки прочтения.
     * Найдено — лента откроется на нём. Раньше загруженного — окно вокруг отметки
     * ([fetchUnread]); после него ([settled]) — у самого старого загруженного чужого.
     */
    private fun placeUnread(settled: Boolean) {
        val source = visible
        if (source.isEmpty()) return
        val window = jumpTime?.let(ranges::around) ?: ranges.live()
        val fromBeginning = window?.let(ranges::startsAtBeginning) == true
        val covered = readMarkMs > 0 && (fromBeginning || source.any { it.timeMs <= readMarkMs && it.status == MessageStatus.SENT })
        val anchor = when {
            covered -> firstUnread(source, readMarkMs, pendingUnread, ::isOutgoing, complete = true)
            readMarkMs > 0 && !settled -> {
                if (latestLoaded) fetchUnread()
                return
            }
            else -> unreadAnchor(source, pendingUnread, ::isOutgoing, complete = latestLoaded || settled)
        } ?: return
        pendingUnread = 0
        unreadAnchorId = anchor
        following = false
        placeChecked = true
        // Открыли на найденном сообщении: разделитель встаёт, но лента остаётся у сообщения.
        if (!openedAtMessage) requestScroll(ScrollRequest.Target.Unread(anchor))
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
                repository.refreshLatest(chatId)
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
                memberList?.load()
                val shared = chat?.peerId?.let { runCatching { source.commonChats(it) }.getOrDefault(emptyList()) }.orEmpty()
                val typeId = when (chat?.type) {
                    ChatType.CHANNEL -> LockPayloads.COMPLAINT_CHANNEL
                    ChatType.PRIVATE -> LockPayloads.COMPLAINT_USER
                    else -> null
                }
                val reasons = if (typeId == null) emptyList() else {
                    runCatching { source.complaintReasons()[typeId].orEmpty() }.getOrDefault(emptyList())
                }
                _tools.update { it.copy(shared = shared, reasons = reasons, busy = false) }
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

    /** Пометить непрочитанным можно любое сообщение с сервера, кроме служебного. */
    fun canMarkUnread(message: Message): Boolean = isServer(message) && !message.isService

    /**
     * Чат снова непрочитан начиная с [message]. После успеха [onLeft] закрывает экран: открытый чат
     * тут же отметился бы прочитанным. Если чат откроют снова, он прочитается как обычно.
     */
    fun markUnread(message: Message, onLeft: () -> Unit) {
        if (!canMarkUnread(message) || markingUnread) return
        markingUnread = true
        viewModelScope.launch {
            try {
                repository.markUnread(chatId, message.timeMs)
                // Явная «непрочитанность» старше любой отметки: следующая отметка сравнивается заново.
                cancelPendingRead()
                markedReadId = null
                sentReadMs = 0L
                onLeft()
            } catch (e: CancellationException) {
                markingUnread = false
                throw e
            } catch (e: Exception) {
                markingUnread = false
                show(e)
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

    /** Выйти из группы или отписаться от канала. [onLeft] — сервер принял, экран закрывается. */
    fun leave(onLeft: () -> Unit) {
        val source = chats ?: return
        viewModelScope.launch {
            try {
                source.leaveChat(chatId)
                onLeft()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                show(e)
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

    /** С кем звонить из этого чата: собеседник личного чата; у групп и ботов — `null`. */
    fun callPeer(): app.orbitle.presentation.calls.CallPeerInfo? {
        val chat = header?.chat ?: return null
        if (chat.type != ChatType.PRIVATE || chat.isBot) return null
        val peer = chat.peerId ?: return null
        return app.orbitle.presentation.calls.CallPeerInfo(peer, chat.title, chat.avatarUrl)
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
        // Подсказки «@»: общий поиск ядра по имени и имени для упоминаний.
        val mentions = if (mention == null) emptyList() else com.max.core.api.MemberSearch.filter(memberRows, mention, ChatMemberRow::name, ChatMemberRow::mentionName).take(8)
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

    /**
     * Плашка под постом канала — только когда у канала включены родные комментарии (опция
     * `COMMENTS: true`). Без опции комментариев нет: обсуждение такого канала, если
     * оно есть, ведёт бот кнопкой под постом, а запросы счётчиков сервер отклоняет.
     */
    private fun commentsFooter(message: Message): Int? {
        if (comments == null || builtFor != ChatType.CHANNEL || !isServer(message) || message.isService) return null
        if (builtComments != true) return null
        return commentCounts[message.id] ?: message.content.comments ?: 0
    }

    /**
     * Спросить счётчики у постов, которых ещё не спрашивали: сначала самые новые (их видно первыми),
     * пачками по [COUNTS_BATCH] с паузой между пачками. Одновременно идёт один запрос; посты,
     * пришедшие за это время, спрашиваются следом. Отказ сервера откладывает повтор: после
     * `too.many.requests` — на остаток общей паузы чтений, иначе на [RETRY_AFTER_ERROR_MS].
     */
    private fun requestCommentCounts() {
        val source = comments ?: return
        if (builtFor != ChatType.CHANNEL || builtComments != true || now() < countsRetryAt) return
        if (countsJob?.isActive == true) return
        val ids = history.asReversed().filter { isServer(it) && !it.isService && it.id !in askedCounts }.map { it.id }
        if (ids.isEmpty()) return
        askedCounts += ids
        countsJob = viewModelScope.launch {
            val chunks = ids.chunked(COUNTS_BATCH)
            for ((index, chunk) in chunks.withIndex()) {
                if (index > 0) delay(COUNTS_PACE_MS)
                val counts = try {
                    source.counts(chatId, chunk)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Эта и следующие пачки спросятся при повторе; остальные пачки сейчас не уходят:
                    // сервер, скорее всего, ответит им той же ошибкой.
                    askedCounts -= chunks.drop(index).flatten().toSet()
                    countsFailed(e)
                    return@launch
                }
                countsFailures = 0
                if (counts.isEmpty()) continue
                commentCounts.putAll(counts)
                rebuild()
            }
            countsJob = null
            requestCommentCounts()
        }
    }

    private fun countsFailed(error: Exception) {
        countsJob = null
        countsFailures += 1
        val wait = if (app.orbitle.data.CoreErrors.map(error).isRateLimit) {
            maxOf(RATE_LIMIT_RETRY_MS, app.orbitle.data.ServerRateLimit.shared.remainingMs() ?: 0L)
        } else {
            RETRY_AFTER_ERROR_MS
        }
        countsRetryAt = now() + wait
        if (countsFailures > COUNTS_RETRIES) return
        countsRetry?.cancel()
        countsRetry = viewModelScope.launch {
            delay(wait)
            requestCommentCounts()
        }
    }

    /** Обсуждение поста можно открыть из меню сообщения: та же проверка, что у плашки под постом. */
    fun canOpenComments(message: Message): Boolean = commentsFooter(message) != null

    fun openComments(post: Message) {
        val source = comments ?: return
        if (_comments.value?.post?.id == post.id) return
        val model = CommentsModel(chatId, post, repository.currentUserId.orEmpty(), source, viewModelScope, formatter, now, knownCount = { commentCounts[post.id] })
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
        // Ушли из чата: отложенный черновик уходит на сервер сейчас.
        draftSync?.flush(chatId)
        // Ушли из чата: его голосовое больше не играет.
        val playing = media.playback.value
        if (playing != null && history.any { it.id == playing.messageId }) media.stopVoice()
    }

    private fun show(error: Exception) {
        val text = app.orbitle.data.CoreErrors.map(error).userMessage
        if (text != null) _messages.value = text
    }

    companion object {
        /** Сообщений в одном запросе реакций. */
        const val REACTIONS_BATCH = 100
        /** Пауза перед повтором реакций и счётчиков после ошибки сервера. */
        const val RETRY_AFTER_ERROR_MS = 30_000L
        /** Постов в одном запросе счётчиков комментариев. */
        const val COUNTS_BATCH = 50
        /** Пауза между пачками счётчиков. */
        const val COUNTS_PACE_MS = 400L
        /** Сколько раз подряд счётчики повторяются сами; дальше — только при обновлении ленты. */
        const val COUNTS_RETRIES = 4
        /** Через сколько повторить свежую страницу после `too.many.requests`. */
        const val RATE_LIMIT_RETRY_MS = 20_000L
        /** Сколько раз сам повторить свежую страницу после `too.many.requests` (паузы 1×, 2×, 4×). */
        const val LATEST_RETRY_LIMIT = 3
        /** Пустой экран, когда сервер так и не отдал историю после повторов. */
        const val RATE_LIMIT_GAVE_UP_HINT = "Сервер не отдаёт сообщения этого чата. Откройте его снова чуть позже"
        /** Пустой экран, пока сервер просит подождать: лента загрузится сама. */
        const val RATE_LIMIT_HINT = "Сервер просит подождать. Сообщения загрузятся сами через несколько секунд"
        /** Пауза перед следующей старой страницей после ошибки. */
        const val OLDER_RETRY_MS = 5_000L
        const val OLDER_AUTO_RETRIES = 3
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
    /** Над этим сообщением встаёт «Непрочитанные сообщения». */
    unreadAnchorId: String? = null,
): List<ChatItem> {
    val result = ArrayList<ChatItem>(history.size + 8)
    // Строится от старых к новым, потом разворачивается.
    var previous: Message? = null
    var previousDay: String? = null
    var dayLabel = ""
    val ordered = if (savedMessages) history.filterNot { SavedMessagesWelcome.isKey(it.text) } else history
    for ((index, message) in ordered.withIndex()) {
        val day = formatter.dayKey(message.timeMs)
        if (day != previousDay) {
            dayLabel = formatter.dayLabel(message.timeMs, nowMs)
            result += ChatItem.Day("day-$day", dayLabel)
            previousDay = day
            previous = null
        }
        if (message.isService) {
            result += ChatItem.Service(message.id, message.text)
            previous = null
            continue
        }
        if (unreadAnchorId != null && message.id == unreadAnchorId) {
            result += ChatItem.Unread
            previous = null
        }
        val next = ordered.getOrNull(index + 1)
        val sameAsPrevious = previous != null && messagesAttach(
            message.authorId, message.timeMs, previous.authorId, previous.timeMs, sameDay = true,
        )
        // Разделитель непрочитанных рвёт серию с обеих сторон, как на iOS.
        val sameAsNext = next != null && !next.isService && next.id != unreadAnchorId && messagesAttach(
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
            day = dayLabel,
        )
        previous = message
    }
    result.reverse()
    return result
}

/** Черновики полей ввода на устройстве: id чата → текст (с разметкой и ответом — [load] / [save]). */
interface DraftStore {
    fun get(chatId: String): String?
    fun put(chatId: String, text: String)

    /** Черновик целиком; хранилище одного текста отдаёт его без времени и отметок. */
    fun load(chatId: String): ChatDraft? = get(chatId)?.takeIf { it.isNotBlank() }?.let { ChatDraft(it, 0L) }

    /** `null` — черновика больше нет. */
    fun save(chatId: String, draft: ChatDraft?) = put(chatId, draft?.text.orEmpty())
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

/**
 * Первое непрочитанное из [unread] последних чужих сообщений (служебные и свои не считаются,
 * как в счётчике сервера). Если ленты не хватает, а она уже сверена с сервером ([complete]), —
 * самое старое чужое сообщение ленты; иначе `null`: ждём историю.
 */
internal fun unreadAnchor(history: List<Message>, unread: Int, isOutgoing: (Message) -> Boolean, complete: Boolean): String? {
    if (unread <= 0) return null
    var seen = 0
    var oldest: String? = null
    for (message in history.asReversed()) {
        if (isOutgoing(message) || message.isService) continue
        seen++
        oldest = message.id
        if (seen == unread) return message.id
    }
    return if (complete) oldest else null
}

/** Кнопка вступления в канал или группу вне списка; [busy] — запрос ушёл. */
data class JoinUi(val label: String, val busy: Boolean)

/** Запуск мини-приложения бота из чата: кнопка «Открыть приложение» или inline-кнопка `OPEN_APP`. */
data class BotAppRequest(val botId: String, val chatId: String, val startParam: String?, val title: String)
