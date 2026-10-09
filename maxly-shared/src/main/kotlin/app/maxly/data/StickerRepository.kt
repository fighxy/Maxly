package app.maxly.data

import app.maxly.domain.AnimatedEmoji
import app.maxly.domain.Sticker
import app.maxly.domain.StickerCatalog
import app.maxly.domain.StickerSet
import com.maxly.shared.MaxClient
import kotlinx.coroutines.CancellationException

/** Каталог стикеров сервера. */
interface StickerRepository {
    suspend fun catalog(): StickerCatalog
    suspend fun stickers(ids: List<String>): List<Sticker>

    /** Анимодзи сервера, тот же каталог, что у реакций. Пустой список — раздел не показывается. */
    suspend fun animatedEmoji(): List<AnimatedEmoji> = emptyList()
}

/** Недавние эмодзи и стикеры панели: хранятся на устройстве. */
interface RecentStickerStore {
    var recentEmoji: List<String>
    var recentStickers: List<Sticker>
}

class CoreStickerRepository(private val client: MaxClient) : StickerRepository {
    private val cache = mutableMapOf<String, Sticker>()

    override suspend fun catalog(): StickerCatalog {
        val sections = MaxCoreGateway.call { client.stickerSections() }
        val ids = (sections.favoriteSetIds + sections.setIds).distinct()
        val sets = if (ids.isEmpty()) emptyList() else ids.chunked(PAGE).flatMap { chunk -> MaxCoreGateway.call { client.stickerSets(chunk) } }
        val byId = sets.associateBy { it.id }
        return StickerCatalog(
            recentIds = sections.recentStickerIds.map(Long::toString),
            sets = ids.mapNotNull(byId::get).map { StickerSet(it.id.toString(), it.name, it.iconUrl, it.stickerIds.map(Long::toString)) },
        )
    }

    override suspend fun stickers(ids: List<String>): List<Sticker> {
        val missing = ids.filter { it !in cache }.mapNotNull { it.toLongOrNull() }.distinct()
        missing.chunked(PAGE).forEach { chunk ->
            MaxCoreGateway.call { client.stickers(chunk) }.forEach { item ->
                cache[item.id.toString()] = Sticker(item.id.toString(), item.url, item.lottieUrl, item.setId?.toString(), item.width, item.height)
            }
        }
        return ids.mapNotNull(cache::get)
    }

    override suspend fun animatedEmoji(): List<AnimatedEmoji> = try {
        MaxCoreGateway.call { client.reactionCatalog() }
            .filter { !it.lottieUrl.isNullOrBlank() || !it.iconUrl.isNullOrBlank() }
            .map { AnimatedEmoji(it.id.toString(), it.emoji, it.iconUrl, it.lottieUrl) }
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        emptyList()
    }

    private companion object {
        const val PAGE = 100
    }
}
