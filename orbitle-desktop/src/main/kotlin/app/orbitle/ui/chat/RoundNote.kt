package app.orbitle.ui.chat

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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.orbitle.domain.Message
import androidx.compose.runtime.collectAsState
import app.orbitle.ui.media.VideoFrame
import app.orbitle.ui.media.rememberVideoPlayer
import app.orbitle.domain.VideoContent
import app.orbitle.presentation.chat.CallBubbleText
import coil3.compose.AsyncImage

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

/**
 * Кружок играет прямо в ленте встроенным проигрывателем: картинка в круге, звук, кольцо
 * прогресса по краю. Доиграв или не открывшись, возвращает пузырь к обложке.
 */
@Composable
private fun RoundPlayer(url: String, userAgent: String, onEnded: () -> Unit) {
    val player = rememberVideoPlayer()
    val state by player.state.collectAsState()
    LaunchedEffect(url) { player.open(url, userAgent) }
    LaunchedEffect(state.ended, state.failed) { if (state.ended || state.failed) onEnded() }
    VideoFrame(state, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
    if (state.frame == null) {
        CircularProgressIndicator(color = Color.White)
    } else {
        CircularProgressIndicator(
            progress = { state.progress },
            modifier = Modifier.fillMaxSize().padding(3.dp),
            color = MaterialTheme.colorScheme.primary,
            strokeWidth = 4.dp,
            trackColor = Color.Transparent,
        )
    }
}
