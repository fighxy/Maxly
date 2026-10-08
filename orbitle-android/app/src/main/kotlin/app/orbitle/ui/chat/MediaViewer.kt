package app.orbitle.ui.chat

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.outlined.Download
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.outlined.Rotate90DegreesCw
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import androidx.media3.ui.compose.SURFACE_TYPE_TEXTURE_VIEW
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.VideoContent
import app.orbitle.media.MediaSources
import app.orbitle.presentation.chat.CallBubbleText
import app.orbitle.presentation.chat.ChatFormatter
import app.orbitle.presentation.chat.MediaViewerState
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

/** Фото и видео сообщения на весь экран: листание, зум фото, своя панель у видео. */
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
        // Страница, которую сейчас увеличили: пока она на экране, пейджер не перехватывает палец.
        var zoomedPage by remember { mutableStateOf<Int?>(null) }
        val scope = rememberCoroutineScope()
        // Поворот фото четвертями по часовой, свой у каждого фото. Счёт не по модулю 4:
        // анимация после четвёртого поворота идёт дальше по часовой, а не крутится назад.
        val turns = remember { androidx.compose.runtime.mutableStateMapOf<String, Int>() }
        val step: (Boolean) -> Unit = { forward ->
            val target = pager.currentPage + if (forward) 1 else -1
            if (target in state.items.indices) scope.launch { pager.animateScrollToPage(target) }
        }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(
                pager,
                Modifier.fillMaxSize(),
                key = { state.items[it].id },
                userScrollEnabled = zoomedPage != pager.currentPage,
            ) { page ->
                val active = pager.currentPage == page
                when (val item = state.items[page]) {
                    is ChatAttachment.Photo -> ZoomablePhoto(
                        url = item.photo.url,
                        turns = turns[item.id] ?: 0,
                        active = active,
                        onChrome = { chrome = !chrome },
                        onStep = step,
                        onClose = onClose,
                        onZoomed = { zoomed ->
                            zoomedPage = when {
                                zoomed -> page
                                zoomedPage == page -> null
                                else -> zoomedPage
                            }
                        },
                    )
                    is ChatAttachment.Video -> VideoPage(
                        video = item.video,
                        url = state.videoUrls[item.id],
                        userAgent = userAgent,
                        active = active,
                        onStep = step,
                        onClose = onClose,
                    )
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
                            CircularProgressIndicator(Modifier.padding(12.dp).size(24.dp), color = Color.White, strokeWidth = 2.dp)
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
 * Фото с зумом 1…5×. Без зума касание края листает, середина прячет шапку, свайп вниз закрывает.
 * Увеличенное едет за пальцем и не отдаёт жест пейджеру. Двойное касание приближает к точке.
 */
@Composable
private fun ZoomablePhoto(
    url: String?,
    turns: Int,
    active: Boolean,
    onChrome: () -> Unit,
    onStep: (forward: Boolean) -> Unit,
    onClose: () -> Unit,
    onZoomed: (Boolean) -> Unit,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var dismissY by remember { mutableFloatStateOf(0f) }
    var imageSize by remember { mutableStateOf(androidx.compose.ui.geometry.Size.Unspecified) }
    val angle by androidx.compose.animation.core.animateFloatAsState(turns * 90f, label = "rotation")
    val scope = rememberCoroutineScope()
    // Повернули — зум и сдвиг сначала.
    LaunchedEffect(turns) {
        scale = 1f
        offset = Offset.Zero
    }
    LaunchedEffect(active, scale) { if (active) onZoomed(scale > 1.01f) else onZoomed(false) }
    DisposableEffect(Unit) { onDispose { onZoomed(false) } }
    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { point ->
                        if (scale > 1.01f) {
                            onChrome()
                        } else {
                            val edge = size.width * 0.22f
                            when {
                                point.x < edge -> onStep(false)
                                point.x > size.width - edge -> onStep(true)
                                else -> onChrome()
                            }
                        }
                    },
                    onDoubleTap = { point ->
                        val target = if (scale > 1f) 1f else 2.5f
                        val startScale = scale
                        val startOffset = offset
                        val endOffset = if (target == 1f) {
                            Offset.Zero
                        } else {
                            val center = Offset(size.width / 2f, size.height / 2f)
                            (center - point) * (target - 1f)
                        }
                        scope.launch {
                            animate(0f, 1f, animationSpec = tween(180)) { t, _ ->
                                scale = startScale + (target - startScale) * t
                                offset = Offset(
                                    startOffset.x + (endOffset.x - startOffset.x) * t,
                                    startOffset.y + (endOffset.y - startOffset.y) * t,
                                )
                            }
                        }
                    },
                )
            }
            .pointerInput(Unit) {
                val slop = viewConfiguration.touchSlop
                val dismissAt = 140.dp.toPx()
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    var total = Offset.Zero
                    // 0 — ещё не ясно, 1 — закрытие вниз, 2 — жест пейджера или зума.
                    var mode = 0
                    do {
                        val event = awaitPointerEvent()
                        val zoom = event.calculateZoom()
                        val pan = event.calculatePan()
                        val multiTouch = event.changes.size > 1
                        if (multiTouch || scale > 1.01f) {
                            mode = 2
                            val next = (scale * zoom).coerceIn(1f, 5f)
                            val limitX = size.width * (next - 1) / 2
                            val limitY = size.height * (next - 1) / 2
                            offset = if (next == 1f) Offset.Zero else Offset(
                                (offset.x + pan.x).coerceIn(-limitX, limitX),
                                (offset.y + pan.y).coerceIn(-limitY, limitY),
                            )
                            scale = next
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        } else {
                            total += pan
                            if (mode == 0 && (abs(total.x) > slop || abs(total.y) > slop)) {
                                mode = if (total.y > slop && total.y > abs(total.x)) 1 else 2
                            }
                            if (mode == 1) {
                                dismissY = total.y.coerceAtLeast(0f)
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        }
                    } while (event.changes.any { it.pressed })
                    if (mode == 1 && dismissY >= dismissAt) onClose()
                    dismissY = 0f
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
                translationY = offset.y + dismissY
            },
        )
    }
}

/**
 * Видео играет здесь же. Касание середины — пауза, края листают, свайп вниз закрывает.
 * Внизу перемотка и время. Играет только видимая страница.
 */
@OptIn(UnstableApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun VideoPage(
    video: VideoContent,
    url: String?,
    userAgent: String,
    active: Boolean,
    onStep: (forward: Boolean) -> Unit,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    var playing by remember { mutableStateOf(false) }
    var ended by remember { mutableStateOf(false) }
    var buffering by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    var dragging by remember { mutableStateOf<Float?>(null) }
    var dismissY by remember { mutableFloatStateOf(0f) }
    val player = remember(url) {
        if (url == null) null else ExoPlayer.Builder(context)
            .setMediaSourceFactory(MediaSources.factory(context, userAgent))
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri(url))
                repeatMode = if (video.isRound) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                prepare()
            }
    }
    DisposableEffect(player) {
        val current = player ?: return@DisposableEffect onDispose {}
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying }
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING
                ended = state == Player.STATE_ENDED
                if (state == Player.STATE_READY) failed = false
                durationMs = current.duration.coerceAtLeast(0L)
            }
            override fun onPlayerError(error: PlaybackException) {
                failed = true
                buffering = false
            }
        }
        current.addListener(listener)
        onDispose {
            current.removeListener(listener)
            current.release()
        }
    }
    LaunchedEffect(player, active) { player?.playWhenReady = active }
    LaunchedEffect(player, active) {
        val current = player ?: return@LaunchedEffect
        while (active) {
            if (dragging == null) positionMs = current.currentPosition.coerceAtLeast(0L)
            val duration = current.duration
            if (duration > 0) durationMs = duration
            delay(100)
        }
    }
    fun toggle() {
        val current = player ?: return
        when {
            // Читаем плеер, а не снимок состояния: жест запоминает эту функцию до конца ролика.
            current.playerError != null -> {
                failed = false
                buffering = true
                current.prepare()
                current.playWhenReady = true
            }
            current.playbackState == Player.STATE_ENDED -> {
                current.seekTo(0)
                current.playWhenReady = true
            }
            current.isPlaying -> current.pause()
            else -> current.play()
        }
    }
    val progress = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
    Box(Modifier.fillMaxSize().graphicsLayer { translationY = dismissY }, contentAlignment = Alignment.Center) {
        AsyncImage(video.posterUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        ContentFrame(
            player = player,
            modifier = Modifier.fillMaxSize(),
            surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
            contentScale = ContentScale.Fit,
            shutter = {},
        )
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(player) {
                    detectTapGestures(onTap = { point ->
                        val edge = size.width * 0.18f
                        when {
                            point.x < edge -> onStep(false)
                            point.x > size.width - edge -> onStep(true)
                            else -> toggle()
                        }
                    })
                }
                .pointerInput(Unit) {
                    val slop = viewConfiguration.touchSlop
                    val dismissAt = 140.dp.toPx()
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        var total = Offset.Zero
                        var closing = false
                        var decided = false
                        do {
                            val event = awaitPointerEvent()
                            total += event.calculatePan()
                            if (!decided && (abs(total.x) > slop || abs(total.y) > slop)) {
                                closing = total.y > slop && total.y > abs(total.x)
                                decided = true
                            }
                            if (closing) {
                                dismissY = total.y.coerceAtLeast(0f)
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        } while (event.changes.any { it.pressed })
                        if (closing && dismissY >= dismissAt) onClose()
                        dismissY = 0f
                    }
                },
        )
        when {
            failed -> IconButton(onClick = { toggle() }) {
                Icon(Icons.Filled.Replay, "Повторить", tint = Color.White, modifier = Modifier.size(72.dp))
            }
            buffering && positionMs == 0L -> CircularProgressIndicator(color = Color.White)
            !playing && !buffering -> Icon(
                if (ended) Icons.Filled.Replay else Icons.Filled.PlayArrow,
                null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(72.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape).padding(8.dp),
            )
        }
        if (player != null) Row(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(Color.Black.copy(alpha = 0.45f))
                .navigationBarsPadding()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { toggle() }) {
                val icon = when {
                    ended || failed -> Icons.Filled.Replay
                    playing -> Icons.Filled.Pause
                    else -> Icons.Filled.PlayArrow
                }
                Icon(icon, if (playing) "Пауза" else "Смотреть", tint = Color.White)
            }
            Text(CallBubbleText.clock(positionMs), color = Color.White, fontSize = 12.sp)
            Spacer(Modifier.width(8.dp))
            Slider(
                value = dragging ?: progress,
                onValueChange = { dragging = it },
                onValueChangeFinished = {
                    dragging?.let { fraction ->
                        if (durationMs > 0) player?.seekTo((durationMs * fraction).toLong())
                    }
                    dragging = null
                },
                enabled = durationMs > 0 && !failed,
                colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.3f)),
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Text(if (durationMs > 0) CallBubbleText.clock(durationMs) else "–:––", color = Color.White, fontSize = 12.sp)
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
