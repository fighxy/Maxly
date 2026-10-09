package app.maxly.presentation.calls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.CallRepository
import app.maxly.data.CoreErrors
import app.maxly.domain.CallOutcome
import app.maxly.domain.CallRecord
import app.maxly.domain.ConnectionState
import app.maxly.presentation.chatlist.ChatAvatar
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/** Строка истории: один звонок или несколько подряд с тем же собеседником. */
data class CallRow(
    val id: String,
    val callIds: List<String>,
    /** Имя со счётчиком: «Иван (2)». */
    val title: String,
    val avatar: ChatAvatar,
    val isGroup: Boolean,
    val isMissed: Boolean,
    val status: String,
    val direction: Direction,
    val dateText: String,
    val chatId: String?,
    val isVideo: Boolean,
    /** Собеседник для «перезвонить»: id пользователя Max, имя без счётчика и аватар. */
    val peerId: String = "",
    val name: String = "",
    val avatarUrl: String? = null,
) {
    enum class Direction { OUTGOING, INCOMING, DOWN }
}

data class CallsUiState(
    val filter: CallsFilter = CallsFilter.ALL,
    val rows: List<CallRow> = emptyList(),
    val content: Content = Content.LOADING,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    /** Бейдж вкладки: пропущенные новее последнего просмотра. */
    val unseenMissed: Int = 0,
    /** Ссылка на только что созданный звонок: экран предлагает ею поделиться. */
    val createdLink: String? = null,
    val isCreatingLink: Boolean = false,
) {
    enum class Content { LOADING, EMPTY, READY }
}

enum class CallsFilter(val title: String) { ALL("Все"), MISSED("Пропущенные") }

/** Где помнить, что уже просмотрено и что скрыто. */
interface CallMarks {
    var lastSeenMs: Long?
    var hiddenIds: Set<String>
}

class InMemoryCallMarks : CallMarks {
    override var lastSeenMs: Long? = null
    override var hiddenIds: Set<String> = emptySet()
}

/** Вкладка «Звонки»: «Все» и «Пропущенные», соседние звонки одного собеседника — одной строкой. */
class CallsViewModel(
    private val repository: CallRepository,
    private val marks: CallMarks = InMemoryCallMarks(),
    private val zone: ZoneId = ZoneId.systemDefault(),
    connection: Flow<ConnectionState>? = null,
    private val now: () -> Long = System::currentTimeMillis,
) : ViewModel() {
    private val _state = MutableStateFlow(CallsUiState())
    val state: StateFlow<CallsUiState> = _state.asStateFlow()

    private var records: List<CallRecord>? = null
    private var hidden: Set<String> = marks.hiddenIds
    private var visible = false

    init {
        // Первый запуск у аккаунта: прежняя история считается просмотренной.
        if (marks.lastSeenMs == null) marks.lastSeenMs = now()
        viewModelScope.launch {
            repository.calls.collect { list ->
                records = list
                if (!list.isNullOrEmpty()) {
                    val pruned = hidden.intersect(list.map { it.id }.toSet())
                    if (pruned != hidden) {
                        hidden = pruned
                        marks.hiddenIds = pruned
                    }
                }
                rebuild()
            }
        }
        // После обрыва журнал загружается заново: звонки, пришедшие офлайн, иначе не видны.
        if (connection != null) viewModelScope.launch {
            var online: Boolean? = null
            connection.collect {
                val now = it == ConnectionState.ONLINE
                if (now && online == false) refresh()
                online = now
            }
        }
    }

    fun setFilter(filter: CallsFilter) {
        if (filter == _state.value.filter) return
        _state.update { it.copy(filter = filter) }
        rebuild()
    }

    /** Вкладка на экране: пропущенные просмотрены, история грузится заново. */
    fun appeared() {
        visible = true
        markSeen()
        refresh()
    }

    fun disappeared() {
        visible = false
    }

    fun refresh() {
        if (_state.value.isRefreshing) return
        _state.update { it.copy(isRefreshing = true) }
        viewModelScope.launch {
            try {
                repository.refresh()
                _state.update { it.copy(error = null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(error = message(e)) }
            } finally {
                _state.update { it.copy(isRefreshing = false) }
                if (records == null) {
                    records = emptyList()
                    rebuild()
                }
            }
        }
    }

    /**
     * Удаляет строку со всеми звонками группы: сразу с экрана, затем на сервере. Ошибка
     * возвращает строку и показывает сообщение.
     */
    fun delete(row: CallRow) {
        val ids = row.callIds.toSet()
        hidden = hidden + ids
        marks.hiddenIds = hidden
        rebuild()
        viewModelScope.launch {
            try {
                repository.delete(row.callIds)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                hidden = hidden - ids
                marks.hiddenIds = hidden
                _state.update { it.copy(error = message(e)) }
                rebuild()
            }
        }
    }

    /** Создаёт групповой звонок; ссылка появляется в [CallsUiState.createdLink]. */
    fun createLink() {
        if (_state.value.isCreatingLink) return
        _state.update { it.copy(isCreatingLink = true) }
        viewModelScope.launch {
            try {
                val link = repository.createLink()
                _state.update { it.copy(createdLink = link, error = null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(error = message(e)) }
            } finally {
                _state.update { it.copy(isCreatingLink = false) }
            }
        }
    }

    fun dismissLink() = _state.update { it.copy(createdLink = null) }

    private fun message(e: Exception) = CoreErrors.text(e)

    fun dismissError() = _state.update { it.copy(error = null) }

    private fun visibleRecords() = records.orEmpty().filterNot { it.id in hidden }

    private fun markSeen() {
        val newest = visibleRecords().maxOfOrNull { it.timeMs } ?: return updateBadge()
        if (newest > (marks.lastSeenMs ?: Long.MIN_VALUE)) marks.lastSeenMs = newest
        updateBadge()
    }

    private fun updateBadge() {
        val seen = marks.lastSeenMs ?: Long.MIN_VALUE
        val count = visibleRecords().count { it.isMissed && it.timeMs > seen }
        _state.update { it.copy(unseenMissed = count) }
    }

    private fun rebuild() {
        if (visible) markSeen() else updateBadge()
        val list = records ?: return
        val filter = _state.value.filter
        val sorted = list.filterNot { it.id in hidden }
            .filter { filter == CallsFilter.ALL || it.isMissed }
            .sortedWith(compareByDescending<CallRecord> { it.timeMs }.thenByDescending { it.id })
        val rows = group(sorted).map(::row)
        _state.update { it.copy(rows = rows, content = if (rows.isEmpty()) CallsUiState.Content.EMPTY else CallsUiState.Content.READY) }
    }

    private fun day(ms: Long) = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()

    private fun group(list: List<CallRecord>): List<List<CallRecord>> {
        val groups = mutableListOf<MutableList<CallRecord>>()
        for (record in list) {
            val last = groups.lastOrNull()?.last()
            if (last != null && last.peerId == record.peerId && kind(last) == kind(record) && day(last.timeMs) == day(record.timeMs)) {
                groups.last() += record
            } else {
                groups += mutableListOf(record)
            }
        }
        return groups
    }

    private fun row(group: List<CallRecord>): CallRow {
        val first = group.first()
        val name = first.title.ifEmpty { if (first.isGroup) "Групповой звонок" else "Без имени" }
        val kind = kind(first)
        return CallRow(
            id = first.id,
            callIds = group.map { it.id },
            title = if (group.size > 1) "$name (${group.size})" else name,
            avatar = ChatAvatar(
                first.avatarUrl?.let { ChatAvatar.Kind.Photo(it, ChatAvatar.initials(name)) } ?: ChatAvatar.Kind.Initials(ChatAvatar.initials(name)),
                ChatAvatar.colorIndex(first.peerId),
            ),
            isGroup = first.isGroup,
            isMissed = kind == Kind.MISSED,
            status = status(kind, first.isVideo),
            direction = when (kind) {
                Kind.OUTGOING -> CallRow.Direction.OUTGOING
                Kind.INCOMING, Kind.MISSED -> CallRow.Direction.INCOMING
                Kind.CANCELLED, Kind.DECLINED -> CallRow.Direction.DOWN
            },
            dateText = dateText(first.timeMs),
            chatId = first.chatId,
            isVideo = first.isVideo,
            peerId = first.peerId,
            name = name,
            avatarUrl = first.avatarUrl,
        )
    }

    enum class Kind { OUTGOING, INCOMING, MISSED, CANCELLED, DECLINED }

    /** Сегодня — время, в этом году — «28 сен», раньше — полная дата. */
    fun dateText(ms: Long): String {
        val date = Instant.ofEpochMilli(ms).atZone(zone)
        val current = Instant.ofEpochMilli(now()).atZone(zone)
        if (date.toLocalDate() == current.toLocalDate()) return "%02d:%02d".format(date.hour, date.minute)
        if (date.year == current.year) return "${date.dayOfMonth} ${MONTHS[date.monthValue - 1]}"
        return "%02d.%02d.%04d".format(date.dayOfMonth, date.monthValue, date.year)
    }

    companion object {
        private val MONTHS = listOf("янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек")

        fun kind(record: CallRecord): Kind = when {
            record.outgoing && record.outcome == CallOutcome.ANSWERED -> Kind.OUTGOING
            !record.outgoing && record.outcome == CallOutcome.ANSWERED -> Kind.INCOMING
            !record.outgoing && record.outcome == CallOutcome.MISSED -> Kind.MISSED
            !record.outgoing && record.outcome == CallOutcome.DECLINED -> Kind.DECLINED
            else -> Kind.CANCELLED
        }

        fun status(kind: Kind, isVideo: Boolean): String {
            val base = when (kind) {
                Kind.OUTGOING -> "Исходящий"
                Kind.INCOMING -> "Входящий"
                Kind.MISSED -> "Пропущенный"
                Kind.CANCELLED -> "Отменённый"
                Kind.DECLINED -> "Отклонённый"
            }
            return if (isVideo) "$base видеозвонок" else base
        }
    }
}
