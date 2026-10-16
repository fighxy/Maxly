package app.maxly.presentation.gifs

import app.maxly.data.gifka.GifkaApi
import app.maxly.data.gifka.GifkaError
import app.maxly.data.gifka.GifkaPingback
import app.maxly.data.gifka.GifkaReportReason
import app.maxly.domain.PhotoContent
import app.maxly.domain.PreparedPhoto
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
    /** Короткое сообщение после жалобы. */
    val notice: String? = null,
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
    private val pingback: GifkaPingback = GifkaPingback(api, scope),
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
                pingback.views(page.items.map { it.id })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, error = message(e)) }
            }
        }
    }

    /**
     * Выбор результата: сообщение встаёт в ленту сразу с превью, GIF качается при отправке.
     * Без ключа — `null` и подсказка.
     */
    fun pick(media: GifkaMedia): PreparedPhoto? {
        if (!_state.value.canSend) {
            _state.update { it.copy(error = NO_KEY) }
            return null
        }
        pingback.click(media.id)
        val preview = PhotoContent(
            id = media.id,
            url = media.webpUrl ?: media.posterUrl,
            width = media.width.takeIf { it > 0 },
            height = media.height.takeIf { it > 0 },
            isGif = true,
            mp4Url = media.mp4Url,
        )
        return PreparedPhoto(preview, prepare = { download(media) }, onSent = { pingback.send(media.id) })
    }

    /** GIF-файл результата как вложение-фото (`.gif` без перекодирования). Ошибка летит наверх. */
    suspend fun download(media: GifkaMedia): OutgoingFile {
        val target = File(File(outgoingDir(), UUID.randomUUID().toString()), "${media.id}.gif")
        val file = api.downloadGif(media, target)
        return OutgoingFile(file.absolutePath, file.name, OutgoingFile.Kind.PHOTO, file.length(), media.width.takeIf { it > 0 }, media.height.takeIf { it > 0 })
    }

    /** Пожаловаться на результат; он сразу пропадает из сетки. */
    fun report(media: GifkaMedia, reason: GifkaReportReason) {
        _state.update { s -> s.copy(items = s.items.filterNot { it.id == media.id }) }
        scope.launch {
            val notice = try {
                api.report(media.id, reason)
                "Жалоба отправлена"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                "Не удалось отправить жалобу"
            }
            _state.update { it.copy(notice = notice) }
        }
    }

    fun noticeShown() = _state.update { it.copy(notice = null) }

    companion object {
        const val EMPTY = "Ничего не нашлось"
        const val NO_KEY = "Отправка гифок из поиска недоступна в этой сборке: нужен ключ gifka.me"
        const val ATTRIBUTION = "Гифки: gifka.me"
        const val ATTRIBUTION_URL = app.maxly.data.gifka.GifkaClient.SITE_URL

        /** «Пожаловаться» в сетке: выключить одним флагом, если не понадобится. */
        const val REPORTS_ENABLED = true

        fun message(e: Throwable): String = when (e) {
            is GifkaError.KeyRequired -> NO_KEY
            is GifkaError -> e.message ?: "Не удалось загрузить гифки"
            else -> "Не удалось загрузить гифки"
        }
    }
}
