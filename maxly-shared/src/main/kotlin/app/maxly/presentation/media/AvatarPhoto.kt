package app.maxly.presentation.media

import app.maxly.domain.ChatAttachment
import app.maxly.domain.PhotoContent
import app.maxly.presentation.chat.MediaViewerState
import app.maxly.presentation.chat.SaveNaming
import com.maxly.core.media.ImageSizes
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Фото профиля человека, группы или канала на весь экран и в файл.
 *
 * Адреса берутся из ядра: сначала оригинал (`avatarFullUrl` у человека, `iconFullUrl` у чата),
 * затем размеренные запасные варианты (`avatarViewerUrls` / `iconViewerUrls`) от большего к
 * меньшему. Квадрат шапки (`avatarUrl`) в этот список не входит: он виден, пока грузится кадр,
 * но не растягивается вместо оригинала. У человека в просмотре и прошлые фото профиля.
 */
object AvatarPhoto {
    /** Просмотр фото профиля отличается от просмотра сообщения этим началом [MediaViewerState.messageId]. */
    const val VIEWER_PREFIX = "avatar:"

    /** Что показать после сохранения. */
    const val SAVED = "Фото сохранено"

    /** Ни один адрес кадра не загрузился. */
    const val FAILED = "Не удалось загрузить фото"

    private val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH.mm.ss", Locale.US)

    /** Кадр просмотра: [id] и адреса в порядке попыток. */
    data class Frame(val id: String, val urls: List<String>, val preview: String? = null)

    /**
     * Адреса в порядке попыток: [fullUrl] (оригинал), затем [viewerUrls] как их дало ядро — от
     * большего к меньшему. Пустые и повторы выкидываются; файл на устройстве — единственный адрес.
     */
    fun candidates(fullUrl: String?, viewerUrls: List<String>): List<String> {
        val full = fullUrl?.trim()?.takeIf { it.isNotEmpty() }
        if (full != null && ImageRequests.isLocal(full)) return listOf(full)
        return (listOfNotNull(full) + viewerUrls.map(String::trim)).filter { it.isNotEmpty() }.distinct()
    }

    /** Прошлое фото профиля из `CONTACT_PHOTOS`: его оригинал, затем размеры ядра. */
    fun historyCandidates(url: String): List<String> =
        candidates(ImageSizes.originalUrl(null, url), ImageSizes.viewerUrls(null, url))

    /** Хоть один адрес протух ([ImageSizes.isExpired]): пора перечитать контакт или чат. */
    fun isExpired(urls: List<String>, nowMillis: Long): Boolean =
        urls.any { !ImageRequests.isLocal(it) && ImageSizes.isExpired(it, nowMillis) }

    /**
     * Первый адрес из [urls], который [load] загрузил, и результат загрузки; `null` — не
     * загрузился ни один. Отмена не глотается.
     */
    suspend fun <T : Any> firstLoaded(urls: List<String>, load: suspend (String) -> T): Pair<String, T>? {
        for (url in urls) {
            try {
                return url to load(url)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
                // Следующий размер.
            }
        }
        return null
    }

    /** Кадр текущего фото профиля [ownerId]; `null` — фото нет. */
    fun current(ownerId: String, fullUrl: String?, viewerUrls: List<String>, preview: String? = null): Frame? =
        candidates(fullUrl, viewerUrls).takeIf { it.isNotEmpty() }?.let { Frame(photoId(ownerId), it, preview?.takeIf(String::isNotBlank)) }

    /**
     * Кадры прошлых фото [ownerId] из [urls] (id фото → адрес, как ответил сервер); фото
     * [currentPhotoId] и совпадающее с текущим [current] пропускаются.
     */
    fun history(ownerId: String, photos: List<Pair<Long?, String>>, currentPhotoId: Long?, current: Frame?): List<Frame> {
        val seen = current?.urls?.firstOrNull()?.let { setOf(it) }.orEmpty()
        return photos.mapIndexedNotNull { i, (id, url) ->
            if (id != null && id == currentPhotoId) return@mapIndexedNotNull null
            val urls = historyCandidates(url).takeIf { it.isNotEmpty() } ?: return@mapIndexedNotNull null
            if (urls.first() in seen) return@mapIndexedNotNull null
            Frame("${photoId(ownerId)}-${id ?: "n$i"}", urls, preview = url)
        }
    }

    /**
     * Просмотр фото профиля [ownerId] (id человека или чата) с подписью [title]: [frames], текущее
     * первым; `null` — кадров нет. Адрес кадра — первый из его списка, пока [ChatMedia] не
     * найдёт загружаемый ([MediaViewerState.fallbacks]).
     */
    fun viewer(ownerId: String, frames: List<Frame>, title: String): MediaViewerState? {
        if (frames.isEmpty()) return null
        return MediaViewerState(
            messageId = VIEWER_PREFIX + ownerId,
            items = frames.map { ChatAttachment.Photo(PhotoContent(id = it.id, url = it.urls.first())) },
            index = 0,
            authorName = title.trim(),
            timeMs = 0,
            previews = frames.mapNotNull { f -> f.preview?.let { f.id to it } }.toMap(),
            fallbacks = frames.associate { it.id to it.urls },
        )
    }

    /** id кадра в просмотре: по нему шапка отдаёт просмотру своё место и картинку. */
    fun photoId(ownerId: String): String = "avatar-$ownerId"

    fun isAvatar(viewer: MediaViewerState?): Boolean = viewer?.messageId?.startsWith(VIEWER_PREFIX) == true

    /** Ключ файла в кэше: свой у каждого адреса, чтобы новое фото не взялось из старого файла. */
    fun cacheId(ownerId: String, url: String): String =
        "avatar-${ownerId.filter { it.isLetterOrDigit() }}-${Integer.toHexString(url.hashCode())}"

    /** «Фото профиля — Анна Смирнова 2026-10-19 15.43.00.jpg»; без имени — «Фото профиля 2026-…». */
    fun fileName(title: String, timeMs: Long, ext: String, zone: ZoneId = ZoneId.systemDefault()): String {
        val time = stamp.format(Instant.ofEpochMilli(timeMs).atZone(zone))
        val name = title.replace(Regex("\\s+"), " ").trim().take(NAME_LIMIT).trim()
        val base = if (name.isEmpty()) "Фото профиля $time" else "Фото профиля — $name $time"
        return SaveNaming.safe("$base.${ext.ifBlank { "jpg" }}")
    }

    /**
     * Файл из «Сохранить как…» для картинки с расширением [ext]: без расширения — дописать его,
     * с расширением другой картинки (предложили `.jpg`, а пришёл PNG) — заменить. Остальное как
     * выбрали.
     */
    fun chosenFile(path: String, ext: String): String {
        val real = ext.ifBlank { "jpg" }.lowercase()
        val name = path.substringAfterLast('/').substringAfterLast('\\')
        val dot = name.lastIndexOf('.')
        if (dot <= 0 || dot == name.lastIndex) return path.trimEnd('.') + ".$real"
        val current = name.substring(dot + 1).lowercase()
        val same = current == real || (current in JPEG && real in JPEG)
        if (current !in IMAGE_EXTENSIONS || same) return path
        return path.substring(0, path.length - current.length) + real
    }

    private const val NAME_LIMIT = 60
    private val JPEG = setOf("jpg", "jpeg")
    private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif")
}
