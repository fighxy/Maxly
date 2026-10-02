package app.orbitle.media

import android.content.Context
import app.orbitle.data.StorageRepository
import app.orbitle.domain.StorageCategory
import app.orbitle.domain.StorageUsage
import coil3.SingletonImageLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Кэш в `cacheDir`: картинки Coil (`image_cache`), скачанные файлы (`files`), копии
 * вложений для отправки (`outgoing`) и всё остальное.
 */
class CacheStorage(private val context: Context) : StorageRepository {
    private val root: File get() = context.cacheDir

    override suspend fun usage(): StorageUsage = withContext(Dispatchers.IO) {
        val photos = SingletonImageLoader.get(context).diskCache?.size ?: size(File(root, IMAGES))
        StorageUsage(
            mapOf(
                StorageCategory.PHOTOS to photos,
                StorageCategory.FILES to size(File(root, FILES)),
                StorageCategory.OUTGOING to size(File(root, OUTGOING)),
                StorageCategory.OTHER to others().sumOf(::size),
            ),
        )
    }

    override suspend fun clear(categories: Set<StorageCategory>) = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        categories.forEach { category ->
            when (category) {
                StorageCategory.PHOTOS -> {
                    val loader = SingletonImageLoader.get(context)
                    loader.diskCache?.clear() ?: File(root, IMAGES).deleteRecursively()
                    loader.memoryCache?.clear()
                }
                StorageCategory.FILES -> File(root, FILES).listFiles()?.forEach { it.deleteRecursively() }
                // Свежие копии могут как раз загружаться: их не трогаем.
                StorageCategory.OUTGOING -> File(root, OUTGOING).listFiles()
                    ?.filter { now - it.lastModified() > BUSY_MS }
                    ?.forEach { it.deleteRecursively() }
                StorageCategory.OTHER -> others().forEach { it.deleteRecursively() }
            }
        }
    }

    private fun others(): List<File> = root.listFiles().orEmpty().filter { it.name !in setOf(IMAGES, FILES, OUTGOING) }

    private fun size(file: File): Long = when {
        file.isFile -> file.length()
        file.isDirectory -> file.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        else -> 0L
    }

    private companion object {
        const val IMAGES = "image_cache"
        const val FILES = "files"
        const val OUTGOING = "outgoing"
        const val BUSY_MS = 10 * 60_000L
    }
}
