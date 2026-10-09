package app.maxly.presentation.chat

import app.maxly.data.CommentsRepository
import app.maxly.data.CoreErrors
import app.maxly.data.ServerRateLimit
import app.maxly.domain.Message
import app.maxly.domain.MessageContent
import app.maxly.domain.MessageReaction
import app.maxly.domain.MessageStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong

data class CommentsState(
    val comments: List<Message> = emptyList(),
    val phase: Phase = Phase.Loading,
    val hasMore: Boolean = true,
    val isLoadingOlder: Boolean = false,
    val draft: String = "",
    /** Ошибка для снекбара, когда комментарии уже на экране. */
    val error: String? = null,
) {
    sealed interface Phase {
        data object Loading : Phase
        data object Loaded : Phase
        data class Failed(val text: String) : Phase
    }

    val canSend: Boolean get() = draft.isNotBlank()
}

/**
 * Комментарии одного поста канала. Первая страница грузится при открытии, более ранние —
 * при прокрутке вверх. Свой комментарий сразу виден со статусом «отправляется» и заменяется
 * ответом сервера; при ошибке он помечается неотправленным, а текст возвращается в поле ввода.
 */
class CommentsModel(
    val chatId: String,
    /** Пост, под которым обсуждение. Рисуется над комментариями. */
    val post: Message,
    private val currentUserId: String,
    private val repository: CommentsRepository,
    private val scope: CoroutineScope,
    private val formatter: ChatFormatter = ChatFormatter(),
    private val now: () -> Long = System::currentTimeMillis,
    pageSize: Int = 30,
    /** Число комментариев поста по ответу сервера, если оно уже есть. */
    private val knownCount: () -> Int? = { null },
    /** Сколько ждать после `too.many.requests`: остаток общей паузы чтений или запасное значение. */
    private val rateLimitWaitMs: () -> Long = { ServerRateLimit.shared.remainingMs() ?: RATE_LIMIT_WAIT_MS },
) {
    private val pageSize = maxOf(1, pageSize)
    private val _state = MutableStateFlow(CommentsState())
    val state: StateFlow<CommentsState> = _state.asStateFlow()
    private var loaded = false
    private val localIds = AtomicLong()
    /** Последний запрос реакции по id комментария: поздние ответы на прежние не применяются. */
    private val pendingReactions = HashMap<String, Long>()
    private var reactionRequest = 0L
    /** Идущая загрузка первой страницы: повторный вызов не шлёт второй запрос. */
    private var firstPage: Job? = null
    /** До этого времени более ранние страницы не спрашиваются (после отказа сервера). */
    private var olderRetryAt = 0L

    val postId: String get() = post.id

    /** Заголовок: число комментариев, пока они не загружены — из счётчика поста. */
    fun title(knownCount: Int? = null): String {
        val known = knownCount ?: post.content.comments ?: 0
        val shown = _state.value.comments.count { it.status != MessageStatus.FAILED }
        // Пока загружены не все, счётчик сервера точнее числа строк на экране.
        val count = when {
            !loaded -> known
            _state.value.hasMore -> maxOf(shown, known)
            else -> shown
        }
        return if (count > 0) commentsLabel(count) else "Комментарии"
    }

    val emptyText: String?
        get() = _state.value.let { if (it.phase == CommentsState.Phase.Loaded && it.comments.isEmpty()) "Пока нет комментариев. Напишите первый." else null }

    fun isOutgoing(message: Message): Boolean = currentUserId.isNotEmpty() && message.authorId == currentUserId

    /** Строки ленты, от новых к старым, как у чата. */
    fun items(): List<ChatItem> = feedItems(_state.value.comments, formatter, now(), isGroup = true, isOutgoing = ::isOutgoing)

    /** Первая загрузка при открытии. Повторный вызов ничего не делает. */
    fun load() {
        if (loaded) return
        reload()
    }

    fun reload() {
        if (firstPage?.isActive == true) return
        if (_state.value.comments.isEmpty()) _state.update { it.copy(phase = CommentsState.Phase.Loading) }
        firstPage = scope.launch {
            var waits = 0
            while (true) {
                try {
                    val expected = knownCount() ?: post.content.comments
                    val page = repository.firstComments(chatId, postId, post.timeMs, expected, pageSize)
                    loaded = true
                    _state.update { current ->
                        val pending = current.comments.filter { it.status != MessageStatus.SENT }
                        current.copy(comments = merged(page, pending), hasMore = page.size >= pageSize, phase = CommentsState.Phase.Loaded)
                    }
                    return@launch
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val error = CoreErrors.map(e)
                    // Сервер просит подождать: ждём паузу и спрашиваем снова, без ошибки на экране.
                    // Повторов немного, чтобы закрытый сервером канал не опрашивался бесконечно.
                    if (error.isRateLimit && waits < RATE_LIMIT_RETRIES) {
                        waits += 1
                        delay(maxOf(MIN_WAIT_MS, rateLimitWaitMs()))
                        continue
                    }
                    val text = error.userMessage ?: "Не удалось загрузить комментарии"
                    _state.update { if (it.comments.isEmpty()) it.copy(phase = CommentsState.Phase.Failed(text)) else it.copy(error = text) }
                    return@launch
                }
            }
        }
    }

    /** Страница раньше самого старого из загруженных. */
    fun loadOlder() {
        val current = _state.value
        val oldest = current.comments.firstOrNull { it.status == MessageStatus.SENT } ?: return
        if (!loaded || !current.hasMore || current.isLoadingOlder) return
        if (now() < olderRetryAt) return
        _state.update { it.copy(isLoadingOlder = true) }
        scope.launch {
            try {
                val page = repository.comments(chatId, postId, oldest.timeMs, pageSize)
                _state.update { it.copy(comments = merged(page, it.comments), hasMore = page.size >= pageSize, isLoadingOlder = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = CoreErrors.map(e)
                // Пауза сервера: следующая прокрутка вверх после неё догрузит страницу, снекбара нет.
                olderRetryAt = now() + if (error.isRateLimit) maxOf(MIN_WAIT_MS, rateLimitWaitMs()) else MIN_WAIT_MS
                _state.update { it.copy(isLoadingOlder = false, error = if (error.isRateLimit) null else error.userMessage) }
            }
        }
    }

    fun setDraft(text: String) = _state.update { it.copy(draft = text) }

    fun consumeError() = _state.update { it.copy(error = null) }

    fun send() {
        val text = _state.value.draft.trim()
        if (text.isEmpty()) return
        val local = Message(
            id = "local-c${localIds.incrementAndGet()}",
            chatId = chatId,
            authorId = currentUserId,
            text = text,
            timeMs = now(),
            status = MessageStatus.SENDING,
        )
        _state.update { it.copy(draft = "", error = null, comments = it.comments + local) }
        scope.launch {
            try {
                val sent = repository.send(text, chatId, postId)
                _state.update { current ->
                    val rest = current.comments.filter { it.id != local.id && it.id != sent.id }
                    current.copy(comments = merged(listOf(sent), rest), phase = CommentsState.Phase.Loaded)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { current ->
                    current.copy(
                        comments = current.comments.map { if (it.id == local.id) it.copy(status = MessageStatus.FAILED) else it },
                        draft = current.draft.ifEmpty { text },
                        error = CoreErrors.map(e).userMessage,
                    )
                }
            }
        }
    }

    /** Повторить неотправленный комментарий. */
    fun retry(id: String) {
        val failed = _state.value.comments.firstOrNull { it.id == id && it.status == MessageStatus.FAILED } ?: return
        val kept = _state.value.draft.takeIf { it.trim() != failed.text }.orEmpty()
        _state.update { it.copy(comments = it.comments.filter { c -> c.id != id }, draft = failed.text) }
        send()
        if (kept.isNotEmpty()) _state.update { it.copy(draft = kept) }
    }

    /** Убрать неотправленный комментарий (его текст уже в поле ввода). */
    fun discard(id: String) = _state.update { s -> s.copy(comments = s.comments.filterNot { it.id == id && it.status == MessageStatus.FAILED }) }

    fun canReact(comment: Message): Boolean = comment.status == MessageStatus.SENT && comment.id.toLongOrNull() != null

    /** Своя реакция: сразу на экране, затем на сервере; отказ возвращает прежнее. */
    fun toggleReaction(comment: Message, emoji: String) {
        val current = _state.value.comments.firstOrNull { it.id == comment.id } ?: return
        if (!canReact(current)) return
        val before = current.content.reactions
        val after = toggled(before, emoji)
        replaceReactions(comment.id, after)
        val request = ++reactionRequest
        pendingReactions[comment.id] = request
        scope.launch {
            try {
                val update = repository.setReaction(chatId, postId, comment.id, after.firstOrNull { it.mine }?.emoji)
                if (pendingReactions[comment.id] != request) return@launch
                pendingReactions.remove(comment.id)
                if (update != null) {
                    val mine = after.firstOrNull { it.mine }?.emoji
                    // Ответ сервера может не назвать свою реакцию: берём её из запроса.
                    replaceReactions(comment.id, if (update.any { it.mine } || mine == null) update else update.map { it.copy(mine = it.emoji == mine) })
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (pendingReactions[comment.id] != request) return@launch
                pendingReactions.remove(comment.id)
                if (_state.value.comments.firstOrNull { it.id == comment.id }?.content?.reactions == after) replaceReactions(comment.id, before)
                _state.update { it.copy(error = ChatViewModel.reactionFailure(e)) }
            }
        }
    }

    private fun replaceReactions(id: String, reactions: List<MessageReaction>) = _state.update { s ->
        s.copy(comments = s.comments.map { if (it.id == id) it.copy(content = it.content.copy(reactions = reactions)) else it })
    }

    companion object {
        /** Сколько раз подряд первая страница ждёт паузу сервера, прежде чем показать ошибку. */
        const val RATE_LIMIT_RETRIES = 3
        /** Пауза, если общая пауза чтений уже кончилась, а сервер всё ещё отказывает. */
        const val RATE_LIMIT_WAIT_MS = 15_000L
        /** Не чаще одного повтора за это время. */
        const val MIN_WAIT_MS = 2_000L

        /** Слияние страниц по id: серверная версия важнее, порядок — по времени. */
        fun merged(incoming: List<Message>, existing: List<Message>): List<Message> {
            val byId = LinkedHashMap<String, Message>()
            existing.forEach { byId[it.id] = it }
            incoming.forEach { byId[it.id] = it }
            return byId.values.sortedWith(compareBy<Message> { it.timeMs }.thenBy { it.id })
        }

        /** Своя реакция [emoji] ставится, повторная снимается, прежняя своя уступает новой. */
        fun toggled(reactions: List<MessageReaction>, emoji: String): List<MessageReaction> {
            val mine = reactions.firstOrNull { it.mine }?.emoji
            val result = reactions.mapNotNull { r ->
                when {
                    r.mine -> r.copy(count = r.count - 1, mine = false).takeIf { it.count > 0 }
                    else -> r
                }
            }.toMutableList()
            if (mine == emoji) return result
            val index = result.indexOfFirst { it.emoji == emoji }
            if (index >= 0) result[index] = result[index].copy(count = result[index].count + 1, mine = true)
            else result += MessageReaction(emoji, 1, true)
            return result
        }
    }
}

/** «Комментировать», «1 комментарий», «3 комментария», «5 комментариев». */
fun commentsLabel(count: Int): String {
    if (count <= 0) return "Комментировать"
    val n = count % 100
    val last = n % 10
    return when {
        n in 11..19 -> "$count комментариев"
        last == 1 -> "$count комментарий"
        last in 2..4 -> "$count комментария"
        else -> "$count комментариев"
    }
}
