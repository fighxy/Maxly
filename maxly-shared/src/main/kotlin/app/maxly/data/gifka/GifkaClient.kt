package app.maxly.data.gifka

import app.maxly.domain.GifkaMedia
import app.maxly.domain.GifkaPage
import app.maxly.domain.GifkaType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Почему gifka.me не ответил. */
sealed class GifkaError(message: String) : Exception(message) {
    /** Лимит запросов: без ключа 60 в минуту и 2000 в сутки с адреса. */
    class RateLimited(val retryAfterSeconds: Long?) : GifkaError("Слишком много запросов к gifka.me, попробуйте позже")
    /** Скачивание GIF без ключа API закрыто. */
    class KeyRequired : GifkaError("Для отправки гифок из поиска нужен ключ gifka.me")
    class Network(cause: Throwable) : GifkaError("Нет связи с gifka.me")
    class Server(val code: Int) : GifkaError("gifka.me не ответил ($code)")
}

/** Каталог gifka.me: поиск, популярное и скачивание GIF. */
interface GifkaApi {
    suspend fun search(query: String, type: GifkaType = GifkaType.GIF, limit: Int = GifkaClient.PAGE, offset: Int = 0): GifkaPage
    suspend fun trending(type: GifkaType = GifkaType.GIF, limit: Int = GifkaClient.PAGE, offset: Int = 0): GifkaPage
    /** Скачать GIF-файл медиа в [target]. Нужен ключ; ссылку берём сразу перед загрузкой и не храним. */
    suspend fun downloadGif(media: GifkaMedia, target: File): File
}

/**
 * REST-клиент https://api.gifka.me. [apiKey] пустой — запросы без ключа (поиск и превью работают,
 * скачивание GIF — нет). Ответы поиска кэшируются в памяти на [cacheTtlMs] (правила API — не дольше суток).
 */
class GifkaClient(
    private val apiKey: String,
    private val http: OkHttpClient = defaultHttp(),
    private val baseUrl: String = "https://api.gifka.me",
    private val cacheTtlMs: Long = 10 * 60_000L,
    private val now: () -> Long = System::currentTimeMillis,
) : GifkaApi {
    private val cache = object : LinkedHashMap<String, Pair<Long, GifkaPage>>(32, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<Long, GifkaPage>>?) = size > 64
    }

    val hasKey: Boolean get() = apiKey.isNotBlank()

    override suspend fun search(query: String, type: GifkaType, limit: Int, offset: Int): GifkaPage =
        page("/v1/search", mapOf("q" to query.trim(), "type" to type.raw, "limit" to "$limit", "offset" to "$offset"))

    override suspend fun trending(type: GifkaType, limit: Int, offset: Int): GifkaPage =
        page("/v1/media/trending", mapOf("type" to type.raw, "limit" to "$limit", "offset" to "$offset"))

    override suspend fun downloadGif(media: GifkaMedia, target: File): File = withContext(Dispatchers.IO) {
        if (!hasKey) throw GifkaError.KeyRequired()
        val url = media.gifDownloadUrl ?: "$baseUrl/v1/media/${media.id}/download/gif"
        // Ключ только в заголовке: в ссылки он попадать не должен.
        val request = Request.Builder().url(url).header("X-Api-Key", apiKey).build()
        val slow = http.newBuilder().readTimeout(60, TimeUnit.SECONDS).build()
        try {
            slow.newCall(request).execute().use { response ->
                check(response)
                target.parentFile?.mkdirs()
                val body = response.body ?: throw GifkaError.Server(response.code)
                target.outputStream().use { body.byteStream().copyTo(it) }
            }
        } catch (e: GifkaError) {
            throw e
        } catch (e: IOException) {
            target.delete()
            throw GifkaError.Network(e)
        }
        if (!GifkaParser.isGif(target)) {
            target.delete()
            throw GifkaError.Server(200)
        }
        target
    }

    private suspend fun page(path: String, params: Map<String, String>): GifkaPage {
        val url = (baseUrl + path).toHttpUrl().newBuilder().apply { params.forEach { (k, v) -> addQueryParameter(k, v) } }.build()
        val key = url.toString()
        synchronized(cache) { cache[key]?.let { (at, page) -> if (now() - at < cacheTtlMs) return page } }
        val page = withContext(Dispatchers.IO) {
            val request = Request.Builder().url(url).apply { if (hasKey) header("X-Api-Key", apiKey) }.build()
            try {
                http.newCall(request).execute().use { response ->
                    check(response)
                    GifkaParser.page(response.body?.string().orEmpty())
                }
            } catch (e: GifkaError) {
                throw e
            } catch (e: IOException) {
                throw GifkaError.Network(e)
            }
        }
        synchronized(cache) { cache[key] = now() to page }
        return page
    }

    private fun check(response: okhttp3.Response) {
        when {
            response.isSuccessful -> Unit
            response.code == 429 -> throw GifkaError.RateLimited(response.header("Retry-After")?.toLongOrNull())
            response.code == 401 || response.code == 403 -> throw GifkaError.KeyRequired()
            else -> throw GifkaError.Server(response.code)
        }
    }

    companion object {
        const val PAGE = 30

        fun defaultHttp(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()
    }
}

/** Разбор ответов gifka.me; незнакомые поля игнорируются, медиа без превью отбрасываются. */
object GifkaParser {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun page(body: String): GifkaPage {
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrElse { throw GifkaError.Server(200) }
        val items = (root["items"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::media) }
        return GifkaPage(items, (root["total"] as? JsonPrimitive)?.intOrNull)
    }

    fun media(item: JsonObject): GifkaMedia? {
        val id = item.string("id") ?: return null
        val status = item.string("status")
        if (status != null && status != "ready") return null
        val type = GifkaType.entries.firstOrNull { it.raw == item.string("type") } ?: return null
        val renditions = (item["renditions"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
        // Для сетки — самое маленькое превью нужного вида.
        fun smallest(kind: String) = renditions.filter { it.string("kind") == kind && it.string("url") != null }
            .minByOrNull { (it["width"] as? JsonPrimitive)?.intOrNull ?: Int.MAX_VALUE }?.string("url")
        val mp4 = smallest("mp4")
        val webp = smallest("webp")
        val poster = smallest("poster_jpeg") ?: smallest("poster")
        if (mp4 == null && webp == null && poster == null) return null
        val download = item["download"] as? JsonObject
        return GifkaMedia(
            id = id,
            type = type,
            title = item.string("title") ?: item.string("altText") ?: "",
            width = (item["width"] as? JsonPrimitive)?.intOrNull ?: 0,
            height = (item["height"] as? JsonPrimitive)?.intOrNull ?: 0,
            mp4Url = mp4,
            webpUrl = webp,
            posterUrl = poster,
            gifDownloadUrl = download?.string("gif"),
        )
    }

    /** Файл начинается с сигнатуры GIF87a/GIF89a. */
    fun isGif(file: File): Boolean = runCatching {
        file.inputStream().use { val head = ByteArray(6); it.read(head) == 6 && String(head, Charsets.US_ASCII).let { s -> s == "GIF87a" || s == "GIF89a" } }
    }.getOrDefault(false)

    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotEmpty() }
}
