package app.orbitle.ui.chat

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.outlined.Download
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.VideoContent
import app.orbitle.media.MediaSources
import app.orbitle.presentation.chat.ChatFormatter
import app.orbitle.presentation.chat.MediaViewerState
import coil3.compose.AsyncImage

/** Фото и видео сообщения на весь экран: листание, зум фото щипком и двойным касанием. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MediaViewer(
    state: MediaViewerState,
    userAgent: String,
    onPage: (Int) -> Unit,
    onClose: () -> Unit,
    /** Сохранить открытое в галерею; `null` — без кнопки. */
    onSave: (() -> Unit)? = null,
    saving: Boolean = false,
) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = onClose)
        val pager = rememberPagerState(initialPage = state.index) { state.items.size }
        LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect(onPage) }
        var chrome by remember { mutableStateOf(true) }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(pager, Modifier.fillMaxSize(), key = { state.items[it].id }) { page ->
                when (val item = state.items[page]) {
                    is ChatAttachment.Photo -> ZoomablePhoto(item.photo.url, onTap = { chrome = !chrome })
                    is ChatAttachment.Video -> VideoPage(item.video, state.videoUrls[item.id], userAgent, active = pager.currentPage == page)
                    else -> Unit
                }
            }
            if (chrome) {
                Row(
                    Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.45f)).statusBarsPadding().padding(horizontal = 4.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Закрыть", tint = Color.White) }
                    Spacer(Modifier.width(4.dp))
                    Column(Modifier.weight(1f)) {
                        Text(state.authorName.ifEmpty { "Медиа" }, color = Color.White, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(viewerDate(state.timeMs), color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.bodySmall)
                    }
                    if (state.items.size > 1) {
                        Text("${pager.currentPage + 1} из ${state.items.size}", color = Color.White, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(end = 12.dp))
                    }
                    if (onSave != null) {
                        if (saving) {
                            androidx.compose.material3.CircularProgressIndicator(Modifier.padding(12.dp).size(24.dp), color = Color.White, strokeWidth = 2.dp)
                        } else {
                            IconButton(onClick = onSave) { Icon(Icons.Outlined.Download, "Сохранить в галерею", tint = Color.White) }
                        }
                    }
                }
            }
        }
    }
}

private fun viewerDate(timeMs: Long): String {
    if (timeMs <= 0) return ""
    val formatter = ChatFormatter()
    return "${formatter.dayLabel(timeMs, System.currentTimeMillis())}, ${formatter.time(timeMs)}"
}

/** Фото с зумом 1…5×: щипок, сдвиг увеличенного, двойное касание. */
@Composable
private fun ZoomablePhoto(url: String?, onTap: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { onTap() },
                    onDoubleTap = { point ->
                        if (scale > 1f) {
                            scale = 1f
                            offset = Offset.Zero
                        } else {
                            scale = 2.5f
                            val center = Offset(size.width / 2f, size.height / 2f)
                            offset = (center - point) * 1.5f
                        }
                    },
                )
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        val zoom = event.calculateZoom()
                        val pan = event.calculatePan()
                        val multiTouch = event.changes.size > 1
                        // Одним пальцем при scale 1 листается пейджер.
                        if (multiTouch || scale > 1f) {
                            val next = (scale * zoom).coerceIn(1f, 5f)
                            val limitX = size.width * (next - 1) / 2
                            val limitY = size.height * (next - 1) / 2
                            offset = if (next == 1f) Offset.Zero else Offset(
                                (offset.x + pan.x).coerceIn(-limitX, limitX),
                                (offset.y + pan.y).coerceIn(-limitY, limitY),
                            )
                            scale = next
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            model = url,
            contentDescription = "Фото",
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize().graphicsLayer {
                scaleX = scale
                scaleY = scale
                translationX = offset.x
                translationY = offset.y
            },
        )
    }
}

/** Видео: Media3 с системными кнопками. Играет только видимая страница. */
@OptIn(UnstableApi::class)
@Composable
private fun VideoPage(video: VideoContent, url: String?, userAgent: String, active: Boolean) {
    val context = LocalContext.current
    if (url == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AsyncImage(video.posterUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            CircularProgressIndicator(color = Color.White)
        }
        return
    }
    val player = remember(url) {
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(MediaSources.factory(context, userAgent))
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri(url))
                repeatMode = if (video.isRound) ExoPlayer.REPEAT_MODE_ONE else ExoPlayer.REPEAT_MODE_OFF
                prepare()
            }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(active) { player.playWhenReady = active }
    AndroidView(
        factory = { PlayerView(it).apply { this.player = player; setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING) } },
        update = { it.player = player },
        modifier = Modifier.fillMaxSize(),
    )
}
