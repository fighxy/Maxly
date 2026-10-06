package app.orbitle.ui.chat

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.outlined.Download
import app.orbitle.platform.BackHandler
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
import androidx.compose.material.icons.outlined.Rotate90DegreesCw
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.runtime.collectAsState
import app.orbitle.ui.media.VideoControls
import app.orbitle.ui.media.VideoFrame
import app.orbitle.ui.media.rememberVideoPlayer
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.orbitle.domain.ChatAttachment
import app.orbitle.media.DesktopVideo
import app.orbitle.domain.VideoContent
import app.orbitle.presentation.chat.ChatFormatter
import app.orbitle.presentation.chat.MediaViewerState
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch

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
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BackHandler(onBack = onClose)
        val pager = rememberPagerState(initialPage = state.index) { state.items.size }
        LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect(onPage) }
        var chrome by remember { mutableStateOf(true) }
        // Поворот фото четвертями по часовой, свой у каждого фото. Счёт не по модулю 4:
        // анимация после четвёртого поворота идёт дальше по часовой, а не крутится назад.
        val turns = remember { androidx.compose.runtime.mutableStateMapOf<String, Int>() }
        // Клавиши просмотра: ←/→ — соседнее, R — повернуть, Ctrl+S — сохранить. Остальное
        // (переход по чатам и прочее) под открытым просмотром не срабатывает, кроме выхода.
        val keyScope = androidx.compose.runtime.rememberCoroutineScope()
        app.orbitle.ui.keys.HotkeyHandler { hotkey ->
            when (hotkey.action) {
                app.orbitle.ui.keys.HotkeyAction.VIEWER_PREVIOUS -> {
                    if (pager.currentPage > 0) keyScope.launch { pager.animateScrollToPage(pager.currentPage - 1) }
                    true
                }
                app.orbitle.ui.keys.HotkeyAction.VIEWER_NEXT -> {
                    if (pager.currentPage < state.items.lastIndex) keyScope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                    true
                }
                app.orbitle.ui.keys.HotkeyAction.ROTATE -> {
                    val photo = state.items.getOrNull(pager.currentPage) as? ChatAttachment.Photo
                    if (photo != null) turns[photo.id] = (turns[photo.id] ?: 0) + 1
                    true
                }
                app.orbitle.ui.keys.HotkeyAction.SAVE -> {
                    if (!saving) onSave?.invoke()
                    true
                }
                app.orbitle.ui.keys.HotkeyAction.QUIT -> false
                else -> true
            }
        }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(pager, Modifier.fillMaxSize(), key = { state.items[it].id }) { page ->
                when (val item = state.items[page]) {
                    is ChatAttachment.Photo -> ZoomablePhoto(item.photo.url, turns[item.id] ?: 0, onTap = { chrome = !chrome })
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
                    val current = state.items.getOrNull(pager.currentPage)
                    if (current is ChatAttachment.Photo) {
                        IconButton(onClick = { turns[current.id] = (turns[current.id] ?: 0) + 1 }) {
                            Icon(Icons.Outlined.Rotate90DegreesCw, "Повернуть", tint = Color.White)
                        }
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

/**
 * Фото с зумом 1…5×: щипок, сдвиг увеличенного, двойное касание. [turns] — поворот четвертями
 * по часовой: повёрнутое на бок фото уменьшается, чтобы целиком влезть в экран.
 */
@Composable
private fun ZoomablePhoto(url: String?, turns: Int, onTap: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var imageSize by remember { mutableStateOf(androidx.compose.ui.geometry.Size.Unspecified) }
    val angle by androidx.compose.animation.core.animateFloatAsState(turns * 90f, label = "rotation")
    // Повернули — зум и сдвиг сначала.
    LaunchedEffect(turns) {
        scale = 1f
        offset = Offset.Zero
    }
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
            onSuccess = { imageSize = it.painter.intrinsicSize },
            modifier = Modifier.fillMaxSize().graphicsLayer {
                val fit = sidewaysFit(imageSize, size, turns)
                scaleX = scale * fit
                scaleY = scale * fit
                rotationZ = angle
                translationX = offset.x
                translationY = offset.y
            },
        )
    }
}

/**
 * Видео играет здесь же, встроенным проигрывателем: касание — пауза, внизу перемотка и время.
 * Играет только видимая страница. Без ffmpeg ролик открывается системным проигрывателем.
 */
@Composable
private fun VideoPage(video: VideoContent, url: String?, userAgent: String, active: Boolean) {
    val player = rememberVideoPlayer()
    val state by player.state.collectAsState()
    var opening by remember { mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    LaunchedEffect(url) { if (url != null) player.open(url, userAgent, autoplay = active) }
    LaunchedEffect(active) { if (!active) player.pause() }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (state.frame == null) AsyncImage(video.posterUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        VideoFrame(
            state,
            Modifier.fillMaxSize().pointerInput(player) { detectTapGestures(onTap = { player.toggle() }) },
        )
        when {
            state.failed -> IconButton(onClick = {
                val link = url ?: return@IconButton
                opening = true
                scope.launch {
                    runCatching { DesktopVideo.play(DesktopVideo.materialize(link, userAgent)) }
                    opening = false
                }
            }) {
                if (opening) CircularProgressIndicator(color = Color.White)
                else Icon(Icons.Filled.PlayArrow, "Открыть видео в системном проигрывателе", tint = Color.White, modifier = Modifier.size(72.dp))
            }
            url == null || (state.isBuffering && state.frame == null) -> CircularProgressIndicator(color = Color.White)
            !state.isPlaying && !state.isBuffering -> Icon(
                if (state.ended) Icons.Filled.Replay else Icons.Filled.PlayArrow,
                null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(72.dp).background(Color.Black.copy(alpha = 0.35f), androidx.compose.foundation.shape.CircleShape).padding(8.dp),
            )
        }
        if (!state.failed && url != null) {
            VideoControls(player, state, Modifier.align(Alignment.BottomCenter))
        }
    }
}

/**
 * Во сколько раз уменьшить фото, повёрнутое на бок ([turns] нечётно), чтобы оно влезло в
 * [box]: вписанная картинка после поворота меняет ширину с высотой. Ровно стоящее — без изменений.
 */
internal fun sidewaysFit(image: androidx.compose.ui.geometry.Size, box: androidx.compose.ui.geometry.Size, turns: Int): Float {
    if (turns % 2 == 0 || image == androidx.compose.ui.geometry.Size.Unspecified || image.width <= 0f || image.height <= 0f || box.width <= 0f || box.height <= 0f) return 1f
    val fitted = minOf(box.width / image.width, box.height / image.height)
    val width = image.width * fitted
    val height = image.height * fitted
    return minOf(box.width / height, box.height / width, 1f)
}
