package app.maxly.ui.chat

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import androidx.media3.ui.compose.SURFACE_TYPE_TEXTURE_VIEW
import app.maxly.media.MediaSources

/**
 * Гифка в пузыре: MP4 без звука по кругу поверх статичного превью [still]. Пока кадра нет,
 * без MP4, с выключенным автовоспроизведением или при ошибке видна картинка с меткой GIF.
 */
@OptIn(UnstableApi::class)
@Composable
internal fun GifMotion(mp4Url: String?, modifier: Modifier, still: @Composable () -> Unit) {
    val media = LocalBubbleMedia.current
    var failed by remember(mp4Url) { mutableStateOf(false) }
    var rendered by remember(mp4Url) { mutableStateOf(false) }
    val play = mp4Url != null && media.gifAutoplay.value && !failed
    Box(modifier) {
        still()
        if (play && mp4Url != null) {
            val context = LocalContext.current
            val player = remember(mp4Url) {
                ExoPlayer.Builder(context).setMediaSourceFactory(MediaSources.factory(context, media.userAgent)).build().apply {
                    volume = 0f
                    repeatMode = Player.REPEAT_MODE_ONE
                    setMediaItem(MediaItem.fromUri(mp4Url))
                    playWhenReady = true
                    prepare()
                }
            }
            DisposableEffect(player) {
                val listener = object : Player.Listener {
                    override fun onPlayerError(error: PlaybackException) { failed = true }
                    override fun onRenderedFirstFrame() { rendered = true }
                }
                player.addListener(listener)
                onDispose {
                    player.removeListener(listener)
                    player.release()
                }
            }
            ContentFrame(
                player = player,
                modifier = Modifier.fillMaxSize(),
                surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
                contentScale = ContentScale.Crop,
                shutter = {},
            )
        }
        if (!play || !rendered) {
            Text(
                "GIF",
                color = Color.White,
                fontSize = 12.sp,
                modifier = Modifier.align(Alignment.TopStart).padding(6.dp).clip(RoundedCornerShape(8.dp))
                    .background(Color.Black.copy(alpha = 0.5f)).padding(horizontal = 6.dp, vertical = 1.dp),
            )
        }
    }
}
