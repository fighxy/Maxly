package app.maxly.presentation.gifs

import app.maxly.data.gifka.GifkaApi
import app.maxly.data.gifka.GifkaError
import app.maxly.domain.GifkaMedia
import app.maxly.domain.GifkaType
import app.maxly.domain.OutgoingFile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

data class GifSearchState(
    val query: String = "",
    val items: List<GifkaMedia> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    /** Без ключа API отправка из поиска недоступна: только просмотр. */
    val canSend: Boolean = false,
    val sendingId: String? = null,
)

/**
 * Вкладка «GIF» панели: пустой запрос — популярное, иначе поиск с паузой [debounceMs].
 * [type] задаёт вид медиа, чтобы позже так же завести вкладку стикеров.
 */
class GifSearchModel(
    private val api: GifkaApi,
    private val scope: CoroutineScope,
    private val outgoingDir: () -> File,
    canSend: Boolean,
    private val type: GifkaType = GifkaType.GIF,
    private val debounceMs: Long = 400,
) {
    private val _state = MutableStateFlow(GifSearchState(canSend = canSend))
    val state: StateFlow<GifSearchState> = _state.asStateFlow()
    private var job: Job? = null

    /** Первое открытие вкладки: популярное. */
    fun open() {
        if (_state.value.items.isEmpty() && job?.isActive != true) load(_state.value.query, delayMs = 0)
    }

    fun onQuery(query: String) {
        if (query == _state.value.query) return
        _state.update { it.copy(query = query) }
        load(query, if (query.isBlank()) 0 else debounceMs)
    }

    fun retry() = load(_state.value.query, 0)

    private fun load(query: String, delayMs: Long) {
        job?.cancel()
        job = scope.launch {
            if (delayMs > 0) delay(delayMs)
            _state.update { it.copy(loading = true, error = null) }
            try {
                val page = if (query.isBlank()) api.trending(type) else api.search(query, type)
                _state.update { it.copy(items = page.items, loading = false, error = if (page.items.isEmpty()) EMPTY else null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, error = message(e)) }
            }
        }
    }

    /** Скачать GIF выбранного результата и отдать как обычное вложение-фото (`.gif` без перекодирования). */
    suspend fun prepare(media: GifkaMedia): OutgoingFile? {
        if (!_state.value.canSend) {
            _state.update { it.copy(error = NO_KEY) }
            return null
        }
        _state.update { it.copy(sendingId = media.id, error = null) }
        return try {
            val target = File(File(outgoingDir(), UUID.randomUUID().toString()), "${media.id}.gif")
            val file = api.downloadGif(media, target)
            OutgoingFile(file.absolutePath, file.name, OutgoingFile.Kind.PHOTO, file.length(), media.width.takeIf { it > 0 }, media.height.takeIf { it > 0 })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(error = message(e)) }
            null
        } finally {
            _state.update { it.copy(sendingId = null) }
        }
    }

    companion object {
        const val EMPTY = "Ничего не нашлось"
        const val NO_KEY = "Отправка гифок из поиска недоступна в этой сборке: нужен ключ gifka.me"
        const val ATTRIBUTION = "Гифки: gifka.me"

        fun message(e: Throwable): String = when (e) {
            is GifkaError.KeyRequired -> NO_KEY
            is GifkaError -> e.message ?: "Не удалось загрузить гифки"
            else -> "Не удалось загрузить гифки"
        }
    }
}
