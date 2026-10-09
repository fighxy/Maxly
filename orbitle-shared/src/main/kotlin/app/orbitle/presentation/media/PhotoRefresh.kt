package app.orbitle.presentation.media

import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.Message
import com.max.core.api.MaxMessage
import com.max.core.media.ImageSizes
import com.max.core.media.PhotoUrlMedia

/** Одно фото, чей адрес пора обновить (код 203). */
data class PhotoRefreshKey(val chatId: Long, val messageId: Long, val photoId: Long)

/**
 * Очередь обновления адресов: без повторов и не чаще, чем позволяет пауза.
 * [maxPerRequest] — сколько фото уходит в одной пачке; ядро само режет запрос по числу сообщений.
 */
class PhotoRefreshQueue(
    var maxPerRequest: Int = 100,
    var minIntervalMs: Long = 1_000,
) {
    private val waiting = ArrayDeque<PhotoRefreshKey>()
    private val seen = HashSet<PhotoRefreshKey>()
    private var lastSentMs: Long? = null

    val pendingCount: Int get() = waiting.size

    fun enqueue(keys: List<PhotoRefreshKey>) {
        for (key in keys) {
            if (key.photoId == 0L) continue
            if (seen.add(key)) waiting.addLast(key)
        }
    }

    /** Следующая пачка. `null`, если очередь пуста или пауза ещё не прошла. */
    fun take(nowMs: Long): List<PhotoRefreshKey>? {
        if (waiting.isEmpty()) return null
        val last = lastSentMs
        if (last != null && nowMs - last < minIntervalMs) return null
        val count = minOf(maxPerRequest.coerceAtLeast(1), waiting.size)
        val batch = List(count) { waiting.removeFirst() }
        lastSentMs = nowMs
        return batch
    }

    /** Неудачная пачка возвращается в очередь и может уйти после паузы. */
    fun requeue(keys: List<PhotoRefreshKey>) {
        keys.forEach { seen.remove(it) }
        enqueue(keys)
    }

    /** Удачный ответ: ключи больше не считаются стоящими в очереди. */
    fun complete(keys: List<PhotoRefreshKey>) {
        keys.forEach { seen.remove(it) }
    }

    companion object {
        /** Пачка ключей в тело запроса 203: одно сообщение — одна запись `media`. */
        fun media(keys: List<PhotoRefreshKey>): List<PhotoUrlMedia> =
            keys.groupBy { it.chatId to it.messageId }.map { (pair, group) ->
                PhotoUrlMedia(pair.first, pair.second, group.map { it.photoId }.distinct())
            }
    }
}

/** Просроченные фото сообщений. Уже обновлённый адрес берётся из [freshUrls] (id фото → адрес). */
object PhotoRefreshKeys {
    fun expired(chatId: Long, messages: List<MaxMessage>, freshUrls: Map<String, String>, nowMs: Long): List<PhotoRefreshKey> {
        val keys = ArrayList<PhotoRefreshKey>()
        for (message in messages) {
            for (item in message.attaches) {
                val map = item as? Map<*, *> ?: continue
                val type = ((map["_type"] as? String) ?: (map["type"] as? String))?.uppercase()
                if (type != "PHOTO") continue
                val photoId = longOf(map["photoId"]) ?: continue
                if (photoId == 0L) continue
                val stored = urlOf(map) ?: continue
                val current = freshUrls[photoId.toString()] ?: stored
                if (!ImageSizes.isExpired(current, nowMs)) continue
                keys += PhotoRefreshKey(chatId, message.id, photoId)
            }
        }
        return keys
    }

    private fun urlOf(map: Map<*, *>): String? =
        listOf("baseUrl", "url").firstNotNullOfOrNull { key -> (map[key] as? String)?.takeIf { it.isNotBlank() } }

    private fun longOf(value: Any?): Long? = when (value) {
        is Long -> value
        is Int -> value.toLong()
        is Short -> value.toLong()
        is Number -> value.toLong()
        is String -> value.toLongOrNull()
        else -> null
    }
}

/** Подменяет адреса фото по id. Пустой адрес и неизвестный id не трогает. */
fun Message.withPhotoUrls(urls: Map<String, String>): Message {
    if (urls.isEmpty()) return this
    var changed = false
    val attachments = content.attachments.map { attachment ->
        val photo = (attachment as? ChatAttachment.Photo)?.photo ?: return@map attachment
        val fresh = urls[photo.id]?.takeIf { it.isNotBlank() } ?: return@map attachment
        if (fresh == photo.url) return@map attachment
        changed = true
        ChatAttachment.Photo(photo.copy(url = fresh))
    }
    return if (changed) copy(content = content.copy(attachments = attachments)) else this
}
