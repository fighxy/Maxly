package app.maxly.presentation.stories

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.CoreErrors
import app.maxly.data.StoriesRepository
import app.maxly.domain.Story
import app.maxly.domain.StoryArchive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Свой архив историй: истории от новых к старым, курсор следующей страницы и что сейчас идёт.
 * [loaded] `false` — первая страница ещё не пришла; [end] — страниц больше нет.
 */
data class StoryArchiveState(
    val stories: List<Story> = emptyList(),
    val marker: Long? = null,
    val loaded: Boolean = false,
    val end: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
) {
    /** Пустой архив: экран показывает «Создать историю». */
    val isEmpty: Boolean get() = loaded && stories.isEmpty()
    val canLoadMore: Boolean get() = loaded && !end && !loading
}

/** Листание архива 219: страницы по 30, курсор `null` или `0` — конец. Чистая логика. */
object StoryArchivePaging {
    /** Первая страница заменяет список, следующая дописывается без повторов. */
    fun apply(state: StoryArchiveState, page: StoryArchive, first: Boolean): StoryArchiveState {
        val base = if (first) emptyList() else state.stories
        val seen = base.mapTo(HashSet()) { it.id }
        val merged = base + page.stories.filter { seen.add(it.id) }
        val marker = page.marker?.takeIf { it != 0L }
        return StoryArchiveState(
            stories = merged,
            marker = marker,
            loaded = true,
            end = marker == null || (!first && page.stories.isEmpty()),
            loading = false,
        )
    }
}

/** Экран «Мои истории». */
class MyStoriesViewModel(private val repository: StoriesRepository) : ViewModel() {
    private val _state = MutableStateFlow(StoryArchiveState())
    val state: StateFlow<StoryArchiveState> = _state.asStateFlow()

    init {
        reload()
    }

    /** Первая страница заново. */
    fun reload() = load(first = true)

    /** Следующая страница, если она есть и ничего не грузится. */
    fun loadMore() {
        if (_state.value.canLoadMore) load(first = false)
    }

    private fun load(first: Boolean) {
        if (_state.value.loading) return
        val marker = if (first) null else _state.value.marker
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            try {
                val page = repository.ownArchive(marker)
                _state.update { StoryArchivePaging.apply(it, page, first) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, error = CoreErrors.text(e)) }
            }
        }
    }
}
