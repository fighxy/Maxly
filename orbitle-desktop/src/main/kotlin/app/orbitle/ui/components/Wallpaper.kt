package app.orbitle.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import app.orbitle.ui.res.painterResource
import app.orbitle.R
import app.orbitle.domain.ChatWallpaper
import app.orbitle.domain.WallpaperImage

/** Обои и тема, выбранные в «Оформлении»: экраны чата читают их отсюда. */
data class ChatBackdrop(val wallpaper: ChatWallpaper = ChatWallpaper.PLAIN, val dark: Boolean = false)

val LocalChatBackdrop = compositionLocalOf { ChatBackdrop() }

fun WallpaperImage.resource(thumb: Boolean = false): Int = when (this) {
    WallpaperImage.AUTUMN -> if (thumb) R.drawable.wallpaper_autumn_thumb else R.drawable.wallpaper_autumn
    WallpaperImage.AUTUMN_DARK -> if (thumb) R.drawable.wallpaper_autumn_dark_thumb else R.drawable.wallpaper_autumn_dark
    WallpaperImage.AUTUMN_NIGHT -> if (thumb) R.drawable.wallpaper_autumn_night_thumb else R.drawable.wallpaper_autumn_night
}

/** Фон ленты: картинка обоев на весь экран или ровный цвет. */
@Composable
fun ChatWallpaperBackground(backdrop: ChatBackdrop, modifier: Modifier = Modifier, thumb: Boolean = false) {
    val image = backdrop.wallpaper.image(backdrop.dark)
    if (image == null) {
        Box(modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLowest))
    } else {
        Image(painterResource(image.resource(thumb)), contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier.fillMaxSize())
    }
}
