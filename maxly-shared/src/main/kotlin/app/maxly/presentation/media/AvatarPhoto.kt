package app.maxly.presentation.media

import app.maxly.domain.ChatAttachment
import app.maxly.domain.PhotoContent
import app.maxly.presentation.chat.MediaViewerState
import app.maxly.presentation.chat.SaveNaming
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Фото профиля человека, группы или канала на весь экран и в файл.
 *
 * Полное качество — адрес аватара из ядра (`baseUrl` у человека, `baseIconUrl` у чата) без
 * параметра `fn`: по [com.maxly.core.media.ImageSizes] адрес без `fn` — оригинал, а `sqr_N` —
 * уменьшенные квадраты для списков. Пока грузится оригинал, в просмотре виден квадрат шапки.
 * Ядро отдаёт одно текущее фото, поэтому просмотр всегда из одного кадра.
 */
object AvatarPhoto {
    /** Просмотр фото профиля отличается от просмотра сообщения этим началом [MediaViewerState.messageId]. */
    const val VIEWER_PREFIX = "avatar:"

    /** Что показать после сохранения. */
    const val SAVED = "Фото сохранено"

    private val stamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH.mm.ss", Locale.US)

    /** Адрес оригинала: [url] без `fn`. Пустой адрес — `null`, файл на устройстве — как есть. */
    fun original(url: String?): String? {
        if (url.isNullOrBlank()) return null
        if (ImageRequests.isLocal(url)) return url
        return withoutFn(url.trim())
    }

    /** Квадрат для шапки и первого кадра просмотра: тот же адрес, что у аватара шапки. */
    fun preview(url: String?, points: Float, density: Float): String? =
        ImageRequests.square(original(url), points, density)

    /**
     * Просмотр фото профиля [ownerId] (id человека или чата) с подписью [title]; `null` — фото
     * нет, открывать нечего. [preview] — уже загруженный квадрат шапки.
     */
    fun viewer(ownerId: String, url: String?, title: String, preview: String? = null): MediaViewerState? {
        val full = original(url) ?: return null
        val photo = PhotoContent(id = photoId(ownerId), url = full)
        return MediaViewerState(
            messageId = VIEWER_PREFIX + ownerId,
            items = listOf(ChatAttachment.Photo(photo)),
            index = 0,
            authorName = title.trim(),
            timeMs = 0,
            previews = preview?.takeIf { it.isNotBlank() }?.let { mapOf(photo.id to it) }.orEmpty(),
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

    /** Адрес без параметра `fn`; остальные параметры (подпись, срок) остаются на месте. */
    private fun withoutFn(url: String): String {
        val question = url.indexOf('?')
        // Ядро дописывает `&fn=` и к адресу без `?`.
        val split = if (question >= 0) question else url.indexOf('&')
        if (split < 0) return url
        val head = url.substring(0, split)
        val kept = url.substring(split + 1).split('&').filter { it.isNotEmpty() && !it.startsWith("fn=") }
        if (kept.isEmpty()) return head
        return head + (if (question >= 0) "?" else "&") + kept.joinToString("&")
    }

    private const val NAME_LIMIT = 60
    private val JPEG = setOf("jpg", "jpeg")
    private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif")
}
