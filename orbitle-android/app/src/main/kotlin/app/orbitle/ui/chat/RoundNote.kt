package app.orbitle.ui.chat

import androidx.annotation.OptIn
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import androidx.media3.ui.compose.SURFACE_TYPE_TEXTURE_VIEW
import app.orbitle.domain.Message
import app.orbitle.domain.VideoContent
import app.orbitle.media.MediaSources
import app.orbitle.presentation.chat.CallBubbleText
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay

/** Видеосообщение-кружок: обложка, касание играет его прямо в ленте со звуком. */
@kotlin.OptIn(ExperimentalFoundationApi::class)
@Composable
fun RoundNote(message: Message, video: VideoContent, onLongPress: () -> Unit, onDoubleTap: () -> Unit = {}, modifier: Modifier = Modifier) {
    val media = LocalBubbleMedia.current
    val round = media.media.value.round?.takeIf { it.videoId == video.id }
    val size = 220.dp
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.3f))
            .combinedClickable(onLongClick = onLongPress, onDoubleClick = onDoubleTap) { media.onVisual(message, app.orbitle.domain.ChatAttachment.Video(video)) }
            .semantics { contentDescription = if (round != null) "Видеосообщение, остановить" else "Видеосообщение, воспроизвести" },
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(video.posterUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        val url = round?.url
        when {
            round == null -> {
                Box(Modifier.size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.PlayArrow, null, tint = Color.White)
                }
                if (video.durationMs > 0) {
                    Text(
                        CallBubbleText.clock(video.durationMs),
                        color = Color.White,
                        fontSize = 12.sp,
                        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 18.dp).clip(RoundedCornerShape(8.dp))
                            .background(Color.Black.copy(alpha = 0.5f)).padding(horizontal = 6.dp, vertical = 1.dp),
                    )
                }
            }
            url == null -> CircularProgressIndicator(color = Color.White)
            else -> RoundPlayer(url, media.userAgent, onEnded = { media.onRoundEnded(video.id) })
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun RoundPlayer(url: String, userAgent: String, onEnded: () -> Unit) {
    val context = LocalContext.current
    var progress by remember { mutableFloatStateOf(0f) }
    val player = remember(url) {
        ExoPlayer.Builder(context).setMediaSourceFactory(MediaSources.factory(context, userAgent)).build().apply {
            setMediaItem(MediaItem.fromUri(url))
            playWhenReady = true
            prepare()
        }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) onEnded()
            }
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    LaunchedEffect(player) {
        while (true) {
            val duration = player.duration
            if (duration > 0) progress = (player.currentPosition.toFloat() / duration).coerceIn(0f, 1f)
            delay(100)
        }
    }
    // TextureView, а не SurfaceView: круглая обрезка и кольцо прогресса рисуются поверх кадра.
    ContentFrame(
        player = player,
        modifier = Modifier.fillMaxSize(),
        surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
        contentScale = ContentScale.Crop,
        shutter = {},
    )
    CircularProgressIndicator(
        progress = { progress },
        modifier = Modifier.fillMaxSize().padding(3.dp),
        color = MaterialTheme.colorScheme.primary,
        strokeWidth = 4.dp,
        trackColor = Color.Transparent,
    )
}
