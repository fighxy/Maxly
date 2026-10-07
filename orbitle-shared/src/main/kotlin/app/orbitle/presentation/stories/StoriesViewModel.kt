package app.orbitle.presentation.stories

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.CoreErrors
import app.orbitle.data.StoriesRepository
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.OutgoingStory
import app.orbitle.domain.Story
import app.orbitle.domain.StoryAudience
import app.orbitle.domain.StoryOwner
import app.orbitle.domain.StoryRing
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch

/**
 * Открытый просмотр историй. [queue] — владельцы по порядку листания, [stories] — истории
 * текущего владельца от старых к новым (пусто, пока грузятся). [epoch] растёт при каждом
 * запуске истории: экран по нему заново запускает таймер, даже если история та же.
 */
data class StoryViewerState(
    val queue: List<StoryRing>,
    val ownerIndex: Int,
    val stories: List<Story> = emptyList(),
    val storyIndex: Int = 0,
    val isLoading: Boolean = true,
    /** Свои истории: в просмотре есть «Удалить». */
    val isOwn: Boolean = false,
    val isDeleting: Boolean = false,
    val epoch: Int = 0,
) {
    val ring: StoryRing get() = queue[ownerIndex]
    val story: Story? get() = stories.getOrNull(storyIndex)
}

data class StoriesUiState(
    /** Своё кольцо, если есть истории: плитка «Ваша история». */
    val own: StoryRing? = null,
    /** Чужие кольца ленты: сначала непросмотренные, затем свежие. */
    val rings: List<StoryRing> = emptyList(),
    /** Кольца владельцев вне ленты (открытый профиль или чат). */
    val peers: Map<String, StoryRing> = emptyMap(),
    val viewer: StoryViewerState? = null,
    /** Идёт публикация: доля загруженного файла. */
    val publishProgress: Float? = null,
    /** Сообщение для снекбара. */
    val message: String? = null,
) {
    /** Кольцо владельца [ownerId] — из ленты или открытого профиля; `null`, если историй нет. */
    fun ringOf(ownerId: String?): StoryRing? {
        if (ownerId.isNullOrEmpty() || ownerId == "0") return null
        if (own?.owner?.id == ownerId) return own
        return rings.firstOrNull { it.owner.id == ownerId } ?: peers[ownerId]
    }

    /** Кольцо на аватаре: человек — по id собеседника, группа и канал — только если владелец того же типа. */
    fun ringFor(ownerId: String?, ownerType: StoryOwner.Type): StoryRing? {
        val ring = ringOf(ownerId) ?: return null
        return ring.takeIf { StoryStripMotion.ringMatches(it, ownerType) }
    }
}

/**
 * Истории: лента колец над списком чатов, кольца на аватарах, просмотр и публикация. Одна
 * модель на весь экран после входа: список, шапка чата и профиль видят одни и те же кольца.
 * Порядок колец и продолжение с первой непросмотренной истории — как у эталонного клиента.
 */
class StoriesViewModel(
    private val repository: StoriesRepository,
    connection: Flow<ConnectionState> = flowOf(ConnectionState.ONLINE),
    private val now: () -> Long = System::currentTimeMillis,
) : ViewModel() {

    private val _state = MutableStateFlow(StoriesUiState())
    val state: StateFlow<StoriesUiState> = _state.asStateFlow()

    /** Кольца ленты по id владельца, включая своё. */
    private var feed: Map<String, StoryRing> = emptyMap()
    private var peers: Map<String, StoryRing> = emptyMap()
    /** Владельцы вне ленты, о которых уже спрашивали. Ключ — тип и id. */
    private val requested = HashSet<String>()
    private val cache = HashMap<String, List<Story>>()
    /** Истории, уже отмеченные просмотренными за этот просмотр. */
    private val marked = HashSet<String>()
    /** Сколько историй владельца было просмотрено, когда его открыли: их не отмечаем снова. */
    private val seenAtOpen = HashMap<String, Int>()
    private var refreshing: Job? = null
    private var loading: Job? = null

    init {
        viewModelScope.launch {
            repository.updates.collect { apply(it) }
        }
        viewModelScope.launch {
            var online = false
            connection.collect {
                val back = it == ConnectionState.ONLINE && !online
                online = it == ConnectionState.ONLINE
                if (back) refresh()
            }
        }
    }

    /** Первая страница ленты заново. Ошибка не показывается: лента просто остаётся прежней. */
    fun refresh() {
        if (refreshing?.isActive == true) return
        refreshing = viewModelScope.launch {
            val rings = try {
                repository.feed()
            } catch (e: Throwable) {
                return@launch
            }
            feed = rings.filterNot { it.isEmpty }.associateBy { it.owner.id }
            publish()
        }
    }

    /**
     * Кольцо владельца вне ленты (человек из открытого профиля или чата): один запрос на
     * владельца за сессию модели.
     */
    fun loadRing(ownerId: String?) = loadOwner(ownerId, StoryOwner.Type.USER)

    /**
     * Кольцо владельца вне ленты: человек из профиля или группа и канал.
     * Один запрос на пару (тип, id) за сессию модели. Только положительные id: на id чата
     * группы или канала (отрицательный) сервер отвечает ошибкой валидации и рвёт соединение.
     */
    fun loadOwner(ownerId: String?, type: StoryOwner.Type) {
        if (ownerId == null || (ownerId.toLongOrNull() ?: 0L) <= 0L) return
        if (ownerId in feed || !requested.add(requestKey(ownerId, type))) return
        viewModelScope.launch {
            val reply = try {
                repository.stories(StoryOwner(ownerId, type))
            } catch (e: Throwable) {
                requested.remove(requestKey(ownerId, type))
                return@launch
            }
            cache[ownerId] = reply.stories.filter { it.media != null }
            peers = if (reply.ring == null) peers - ownerId else peers + (ownerId to reply.ring)
            publish()
        }
    }

    /** Открывает истории [ownerId]: свои — только свои, чужие — с листанием по ленте. */
    fun open(ownerId: String) {
        val me = repository.currentUserId
        val ring = _state.value.ringOf(ownerId) ?: return
        val queue: List<StoryRing>
        val index: Int
        val rings = _state.value.rings
        when {
            ownerId == me -> {
                queue = listOf(ring)
                index = 0
            }
            rings.any { it.owner.id == ownerId } -> {
                queue = rings
                index = rings.indexOfFirst { it.owner.id == ownerId }
            }
            else -> {
                queue = listOf(ring)
                index = 0
            }
        }
        marked.clear()
        seenAtOpen.clear()
        _state.value = _state.value.copy(viewer = StoryViewerState(queue, index, isOwn = ownerId == me))
        showOwner(index)
    }

    /** Следующая история; после последней — следующий владелец, после последнего — закрытие. */
    fun next() {
        val viewer = _state.value.viewer ?: return
        if (viewer.storyIndex + 1 < viewer.stories.size) start(viewer.storyIndex + 1) else nextOwner()
    }

    /** Предыдущая история; на первой — предыдущий владелец. */
    fun previous() {
        val viewer = _state.value.viewer ?: return
        if (viewer.storyIndex > 0) start(viewer.storyIndex - 1) else previousOwner()
    }

    fun nextOwner() {
        val viewer = _state.value.viewer ?: return
        if (viewer.ownerIndex + 1 < viewer.queue.size) showOwner(viewer.ownerIndex + 1) else close()
    }

    fun previousOwner() {
        val viewer = _state.value.viewer ?: return
        if (viewer.ownerIndex > 0) showOwner(viewer.ownerIndex - 1) else start(0)
    }

    fun close() {
        loading?.cancel()
        _state.value = _state.value.copy(viewer = null)
    }

    /** Удаляет текущую свою историю и идёт к следующей; последнюю — закрывает просмотр. */
    fun deleteCurrent() {
        val viewer = _state.value.viewer ?: return
        val story = viewer.story ?: return
        if (!viewer.isOwn || viewer.isDeleting) return
        updateViewer { it.copy(isDeleting = true) }
        viewModelScope.launch {
            try {
                repository.delete(listOf(story.id))
            } catch (e: Throwable) {
                updateViewer { it.copy(isDeleting = false) }
                fail(e, "Не удалось удалить историю")
                return@launch
            }
            val ownerId = story.owner.id
            val left = viewer.stories.filterNot { it.id == story.id }
            cache[ownerId] = left
            shrink(ownerId)
            val current = _state.value.viewer ?: return@launch
            if (left.isEmpty()) {
                close()
            } else {
                _state.value = _state.value.copy(viewer = current.copy(stories = left, isDeleting = false))
                start(viewer.storyIndex.coerceAtMost(left.size - 1))
            }
        }
    }

    /** Публикует историю. Пока идёт загрузка, [StoriesUiState.publishProgress] не `null`. */
    fun publish(story: OutgoingStory, audience: StoryAudience) {
        if (_state.value.publishProgress != null) return
        _state.value = _state.value.copy(publishProgress = 0f)
        viewModelScope.launch {
            val ring = try {
                repository.publish(story, audience) { p -> _state.value = _state.value.copy(publishProgress = p) }
            } catch (e: Throwable) {
                _state.value = _state.value.copy(publishProgress = null)
                fail(e, "Не удалось опубликовать историю")
                return@launch
            }
            val me = repository.currentUserId
            if (me != null) {
                cache.remove(me)
                val old = feed[me]
                val next = ring ?: StoryRing(
                    owner = StoryOwner(me),
                    name = old?.name.orEmpty(),
                    avatarUrl = old?.avatarUrl,
                    updatedAtMs = now(),
                    total = (old?.total ?: 0) + 1,
                    read = old?.read ?: 0,
                )
                feed = feed + (me to next)
            }
            _state.value = _state.value.copy(publishProgress = null, message = "История опубликована")
            publish()
        }
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    /** Пуш кольца: пустое убирается, остальное встаёт в ленту. */
    private fun apply(ring: StoryRing) {
        val id = ring.owner.id
        if (ring.isEmpty) {
            feed = feed - id
            peers = peers - id
            cache.remove(id)
        } else {
            if (feed[id]?.total != ring.total) cache.remove(id)
            feed = feed + (id to ring.withProfile(feed[id] ?: peers[id]))
            peers = peers - id
        }
        publish()
    }

    private fun showOwner(index: Int) {
        val viewer = _state.value.viewer ?: return
        val ring = viewer.queue.getOrNull(index) ?: return
        val ownerId = ring.owner.id
        loading?.cancel()
        val cached = cache[ownerId]
        updateViewer { it.copy(ownerIndex = index, stories = cached.orEmpty(), storyIndex = 0, isLoading = cached == null) }
        if (cached != null) {
            begin(ring, cached)
            return
        }
        loading = viewModelScope.launch {
            val reply = try {
                repository.stories(ring.owner)
            } catch (e: Throwable) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                fail(e, "Не удалось загрузить истории")
                close()
                return@launch
            }
            val stories = reply.stories.filter { it.media != null }
            cache[ownerId] = stories
            reply.ring?.let { fresh -> replaceRing(fresh.withProfile(ring)) }
            if (_state.value.viewer?.ownerIndex != index) return@launch
            updateViewer { it.copy(stories = stories, isLoading = false) }
            begin(_state.value.viewer?.ring ?: ring, stories)
        }
    }

    /** Первая история владельца: первая непросмотренная, если такая есть. Пустого — пропускаем. */
    private fun begin(ring: StoryRing, stories: List<Story>) {
        if (stories.isEmpty()) {
            nextOwner()
            return
        }
        seenAtOpen.getOrPut(ring.owner.id) { ring.read }
        start(resumeIndex(ring, stories.size))
    }

    private fun start(index: Int) {
        val viewer = _state.value.viewer ?: return
        if (viewer.stories.isEmpty()) return
        val i = index.coerceIn(0, viewer.stories.size - 1)
        updateViewer { it.copy(storyIndex = i, epoch = it.epoch + 1, isLoading = false) }
        markSeen(viewer.ring, viewer.stories[i], i)
    }

    /** Отмечает историю просмотренной один раз; уже просмотренные до открытия не отмечаются. */
    private fun markSeen(ring: StoryRing, story: Story, index: Int) {
        if (story.owner.id == repository.currentUserId) return
        if (index < (seenAtOpen[ring.owner.id] ?: 0) || !marked.add(story.id)) return
        // Кольцо гаснет сразу, не дожидаясь ответа сервера.
        val current = _state.value.ringOf(ring.owner.id) ?: ring
        val previousRead = current.read
        replaceRing(current.copy(read = (current.read + 1).coerceAtMost(current.total)))
        viewModelScope.launch {
            val sent = runCatching { repository.markSeen(story.owner, story.id) }.isSuccess
            if (sent) return@launch
            marked.remove(story.id)
            val now = _state.value.ringOf(ring.owner.id) ?: return@launch
            if (now.read == (previousRead + 1).coerceAtMost(now.total)) replaceRing(now.copy(read = previousRead))
        }
    }

    /** Свои истории после удаления одной: кольцо короче, пустое — убирается. */
    private fun shrink(ownerId: String) {
        val ring = feed[ownerId] ?: return
        val total = (ring.total - 1).coerceAtLeast(0)
        feed = if (total == 0) feed - ownerId else feed + (ownerId to ring.copy(total = total, read = ring.read.coerceAtMost(total)))
        publish()
    }

    private fun replaceRing(ring: StoryRing) {
        val id = ring.owner.id
        when {
            id in feed -> feed = feed + (id to ring)
            id in peers -> peers = peers + (id to ring)
            else -> return
        }
        publish()
    }

    private fun publish() {
        val me = repository.currentUserId
        val rings = order(feed.values.filter { it.owner.id != me })
        val viewer = _state.value.viewer?.let { v ->
            v.copy(queue = v.queue.map { feed[it.owner.id] ?: peers[it.owner.id] ?: it })
        }
        _state.value = _state.value.copy(
            own = me?.let { feed[it] },
            rings = rings,
            peers = peers,
            viewer = viewer,
        )
    }

    private fun updateViewer(change: (StoryViewerState) -> StoryViewerState) {
        val viewer = _state.value.viewer ?: return
        _state.value = _state.value.copy(viewer = change(viewer))
    }

    private fun fail(e: Throwable, fallback: String) {
        val error = CoreErrors.map(e)
        if (error == OrbitleError.Cancelled) return
        val text = if (error == OrbitleError.Unknown) fallback else error.message ?: fallback
        _state.value = _state.value.copy(message = text)
    }

    companion object {
        /** Сначала непросмотренные, затем свежие. */
        fun order(rings: Collection<StoryRing>): List<StoryRing> =
            rings.sortedWith(compareByDescending<StoryRing> { it.hasUnread }.thenByDescending { it.updatedAtMs })

        /** С первой непросмотренной истории, если просмотрена часть; иначе с начала. */
        fun resumeIndex(ring: StoryRing, size: Int): Int =
            if (ring.read in 1 until size) ring.read else 0

        private fun StoryRing.withProfile(known: StoryRing?): StoryRing =
            if (known == null) this else copy(name = name.ifBlank { known.name }, avatarUrl = avatarUrl ?: known.avatarUrl)

        private fun requestKey(ownerId: String, type: StoryOwner.Type) = "${type.code}:$ownerId"
    }
}
