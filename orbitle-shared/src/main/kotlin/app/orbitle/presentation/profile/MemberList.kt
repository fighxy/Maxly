package app.orbitle.presentation.profile

import app.orbitle.data.ChatMembersSource
import app.orbitle.data.ChatPerson
import app.orbitle.data.CoreErrors
import app.orbitle.data.matching
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Участники чата на экране (правила общие с iOS, `test-fixtures/members`): страницы по `marker`
 * и поиск. Порядок — владелец, админы, остальные ([ranked]). Поиск сначала среди загруженных;
 * пока загружены не все страницы, ещё и на сервере — [found], его ответ по [query].
 */
data class MemberListState(
    val members: List<ChatPerson> = emptyList(),
    val query: String = "",
    val found: List<ChatPerson>? = null,
    val loading: Boolean = false,
    val searching: Boolean = false,
    val hasMore: Boolean = false,
    val loaded: Boolean = false,
    val error: String? = null,
) {
    val isSearch: Boolean get() = query.isNotBlank()

    /**
     * Что показать списком. При поиске — совпадения среди загруженных, за ними найденные
     * сервером ([found]) без повторов.
     */
    val visible: List<ChatPerson> get() {
        if (!isSearch) return members
        val local = members.matching(query)
        val ids = local.mapTo(HashSet()) { it.id }
        return local + found.orEmpty().filter { ids.add(it.id) }
    }

    /** Подпись под списком, когда в нём никого. */
    val emptyText: String? get() = when {
        visible.isNotEmpty() || loading || searching -> null
        isSearch -> "Никого не нашлось"
        loaded -> "Список пуст"
        else -> null
    }

    companion object {
        /** Значок у имени: «владелец»; у админа — его подпись, без неё «админ»; у остальных пусто. */
        fun roleLabel(person: ChatPerson): String = when (person.role) {
            ChatPerson.Role.OWNER -> "владелец"
            ChatPerson.Role.ADMIN -> person.alias?.trim()?.takeIf { it.isNotEmpty() } ?: "админ"
            ChatPerson.Role.MEMBER -> ""
        }

        /** Порядок экрана: владелец, админы, остальные — каждый в порядке сервера. */
        fun ranked(people: List<ChatPerson>): List<ChatPerson> =
            people.filter { it.role == ChatPerson.Role.OWNER } +
                people.filter { it.role == ChatPerson.Role.ADMIN } +
                people.filter { it.role == ChatPerson.Role.MEMBER }
    }
}

class MemberList(
    private val scope: CoroutineScope,
    private val source: ChatMembersSource,
    private val chatId: String,
    private val searchDelayMs: Long = SEARCH_DELAY_MS,
) {
    private val _state = MutableStateFlow(MemberListState())
    val state: StateFlow<MemberListState> = _state.asStateFlow()

    private var next: Long? = null
    /** Загружены все страницы: искать на сервере незачем. */
    private var complete = false
    private var paging: Job? = null
    private var search: Job? = null

    /** Первая страница заново (после открытия или изменений состава). */
    fun load() {
        paging?.cancel()
        next = null
        complete = false
        paging = scope.launch { page(reset = true) }
        val query = _state.value.query
        if (query.isNotBlank()) search(query)
    }

    /** Следующая страница, если она есть и не грузится. */
    fun loadMore() {
        val current = _state.value
        if (current.loading || !current.hasMore || current.isSearch) return
        paging = scope.launch { page(reset = false) }
    }

    /**
     * Поиск, как в вебе: совпадения среди загруженных видны сразу; сервер (`{chatId, type, query}`,
     * без страниц) спрашивается после паузы [searchDelayMs] и только если загружены не все.
     */
    fun search(query: String) {
        search?.cancel()
        val term = query.trim()
        val remote = term.isNotEmpty() && !complete
        _state.update { it.copy(query = query, found = null, searching = remote, error = null) }
        if (!remote) return
        search = scope.launch {
            delay(searchDelayMs)
            try {
                val found = source.searchMembers(chatId, term)
                if (_state.value.query.trim() == term) _state.update { it.copy(found = found, searching = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Остаются совпадения среди загруженных.
                if (_state.value.query.trim() == term) _state.update { it.copy(searching = false, error = message(e, "Поиск не удался")) }
            }
        }
    }

    private suspend fun page(reset: Boolean) {
        val marker = if (reset) null else next ?: return
        _state.update { it.copy(loading = true, error = null) }
        try {
            val page = source.memberPage(chatId, marker)
            val known = if (reset) emptyList() else _state.value.members
            val ids = known.mapTo(HashSet()) { it.id }
            // Повторы выбрасываются (остаётся первый); страница без новых — конец списка.
            val added = page.members.filter { ids.add(it.id) }
            next = page.next?.takeIf { added.isNotEmpty() }
            complete = next == null
            _state.update {
                it.copy(members = MemberListState.ranked(known + added), loading = false, loaded = true, hasMore = next != null)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(loading = false, loaded = true, error = message(e, "Не удалось загрузить участников")) }
        }
    }

    private fun message(e: Exception, fallback: String): String = CoreErrors.map(e).userMessage ?: fallback

    companion object {
        /** Пауза после последней буквы перед поиском на сервере (как в вебе). */
        const val SEARCH_DELAY_MS = 200L
    }
}
