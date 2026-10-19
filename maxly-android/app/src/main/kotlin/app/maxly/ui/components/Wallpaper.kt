package app.maxly.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.painterResource
import app.maxly.R
import app.maxly.domain.ChatWallpaper
import app.maxly.domain.ResolvedWallpaper
import app.maxly.domain.WallpaperImage
import app.maxly.domain.WallpaperPhoto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Обои и тема, выбранные в «Оформлении»: экраны чата читают их отсюда. [resolved] — итог с учётом
 * своего фото: общего из «Обоев чата» или своего у чата (оно важнее).
 */
data class ChatBackdrop(
    val wallpaper: ChatWallpaper = ChatWallpaper.PLAIN,
    val dark: Boolean = false,
    val resolved: ResolvedWallpaper = ResolvedWallpaper.Preset,
) {
    val photo: WallpaperPhoto? get() = (resolved as? ResolvedWallpaper.Photo)?.photo

    /** За лентой картинка, а не ровный цвет: чужие пузыри в светлой теме делаются белыми. */
    val hasImage: Boolean get() = when (resolved) {
        is ResolvedWallpaper.Photo -> true
        ResolvedWallpaper.Plain -> false
        ResolvedWallpaper.Preset -> wallpaper.image(dark) != null
    }
}

val LocalChatBackdrop = compositionLocalOf { ChatBackdrop() }

fun WallpaperImage.resource(thumb: Boolean = false): Int = when (this) {
    WallpaperImage.AUTUMN -> if (thumb) R.drawable.wallpaper_autumn_thumb else R.drawable.wallpaper_autumn
    WallpaperImage.AUTUMN_DARK -> if (thumb) R.drawable.wallpaper_autumn_dark_thumb else R.drawable.wallpaper_autumn_dark
    WallpaperImage.AUTUMN_NIGHT -> if (thumb) R.drawable.wallpaper_autumn_night_thumb else R.drawable.wallpaper_autumn_night
}

/**
 * Готовые картинки своих обоев по пути файла. Файл читается один раз: лента, меню и поле ввода
 * берут одну и ту же картинку, при прокрутке ничего не декодируется.
 */
object WallpaperBitmaps {
    private const val LIMIT = 3
    private val cache = LinkedHashMap<String, ImageBitmap>(LIMIT, 0.75f, true)

    fun cached(path: String): ImageBitmap? = synchronized(cache) { cache[path] }

    suspend fun load(path: String): ImageBitmap? {
        cached(path)?.let { return it }
        val bitmap = withContext(Dispatchers.IO) { runCatching { decodeWallpaperFile(path) }.getOrNull() } ?: return null
        synchronized(cache) {
            cache[path] = bitmap
            while (cache.size > LIMIT) cache.remove(cache.keys.first())
        }
        return bitmap
    }
}

/**
 * Фон ленты: своё фото, картинка обоев или ровный цвет. Фото режется по центру под размер
 * области (без растяжения) — при смене размера окна обрезка пересчитывается сама.
 */
@Composable
fun ChatWallpaperBackground(backdrop: ChatBackdrop, modifier: Modifier = Modifier, thumb: Boolean = false) {
    val photo = backdrop.photo
    if (photo != null) {
        PhotoBackground(photo, modifier)
        return
    }
    val image = if (backdrop.resolved == ResolvedWallpaper.Plain) null else backdrop.wallpaper.image(backdrop.dark)
    if (image == null) {
        Box(modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLowest))
    } else {
        Image(painterResource(image.resource(thumb)), contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier.fillMaxSize())
    }
}

@Composable
private fun PhotoBackground(photo: WallpaperPhoto, modifier: Modifier) {
    val bitmap by produceState(WallpaperBitmaps.cached(photo.path), photo.path) { value = WallpaperBitmaps.load(photo.path) }
    Box(modifier.fillMaxSize().clipToBounds().background(MaterialTheme.colorScheme.surfaceContainerLowest)) {
        bitmap?.let {
            Image(
                it,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().then(if (photo.blur) Modifier.blur(18.dp) else Modifier),
            )
        }
        if (photo.dimPercent > 0) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = photo.dimPercent / 100f)))
    }
}
