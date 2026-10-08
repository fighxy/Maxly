package app.orbitle.presentation.profile

import app.orbitle.data.ChatMembersSource
import app.orbitle.data.ChatPerson
import app.orbitle.data.CoreErrors
import app.orbitle.data.MemberSearch
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
 * Участники чата на экране: страницы по `marker` и поиск. [found] — ответ поиска по [query];
 * пока он не пришёл, видны совпадения среди уже загруженных.
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

    /** Что показать списком. */
    val visible: List<ChatPerson> get() = if (!isSearch) members else found ?: MemberSearch.filter(members, query)

    /** Подпись под списком, когда в нём никого. */
    val emptyText: String? get() = when {
        visible.isNotEmpty() || loading || searching -> null
        isSearch -> "Никого не нашлось"
        loaded -> "Список пуст"
        else -> null
    }

    companion object {
        /** Роль под именем: «владелец», «админ» (с подписью админа, если есть), у остальных пусто. */
        fun roleLabel(person: ChatPerson): String = when (person.role) {
            ChatPerson.Role.OWNER -> "владелец"
            ChatPerson.Role.ADMIN -> listOfNotNull("админ", person.alias?.takeIf { it.isNotBlank() }).joinToString(" · ")
            ChatPerson.Role.MEMBER -> ""
        }
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
    private var paging: Job? = null
    private var search: Job? = null

    /** Первая страница заново (после открытия или изменений состава). */
    fun load() {
        paging?.cancel()
        next = null
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

    fun search(query: String) {
        search?.cancel()
        _state.update { it.copy(query = query, found = null, searching = query.isNotBlank(), error = null) }
        val term = query.trim()
        if (term.isEmpty()) return
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
            next = page.next
            _state.update {
                val members = if (reset) page.members else (it.members + page.members).distinctBy { p -> p.id }
                it.copy(members = members, loading = false, loaded = true, hasMore = page.next != null)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(loading = false, loaded = true, error = message(e, "Не удалось загрузить участников")) }
        }
    }

    private fun message(e: Exception, fallback: String): String = CoreErrors.map(e).userMessage ?: fallback

    companion object {
        const val SEARCH_DELAY_MS = 350L
    }
}
