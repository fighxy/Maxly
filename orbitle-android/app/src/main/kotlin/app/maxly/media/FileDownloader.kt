package app.maxly.media

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext

/** Загрузка файлов сообщений в кэш приложения. Готовый файл повторно не качается. */
class FileDownloader(context: Context, private val userAgent: () -> String) {
    private val root = File(context.cacheDir, "files")
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /** Файл [fileId] с именем [name], если уже скачан. */
    fun cached(fileId: String, name: String): File? = target(fileId, name).takeIf { it.isFile && it.length() > 0 }

    /** Скачать по [url]; [progress] получает долю 0…1, когда сервер назвал размер. */
    suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit = {}): File = withContext(Dispatchers.IO) {
        cached(fileId, name)?.let { return@withContext it }
        val target = target(fileId, name)
        target.parentFile?.mkdirs()
        val partial = File(target.parentFile, target.name + ".part")
        val request = Request.Builder().url(url).header("User-Agent", userAgent()).build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
            val body = response.body ?: throw IOException("empty body")
            val total = body.contentLength()
            body.byteStream().use { input ->
                partial.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    while (true) {
                        coroutineContext.ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        done += read
                        if (total > 0) progress((done.toFloat() / total).coerceIn(0f, 1f))
                    }
                }
            }
        }
        if (!partial.renameTo(target)) throw IOException("rename failed")
        target
    }

    private fun target(fileId: String, name: String): File {
        val safe = name.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_").trim().ifEmpty { "file" }.take(120)
        return File(File(root, fileId.replace(Regex("[^A-Za-z0-9_-]"), "_")), safe)
    }
}
