package app.maxly.ui.chat

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Rotate90DegreesCw
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import androidx.media3.ui.compose.SURFACE_TYPE_TEXTURE_VIEW
import app.maxly.domain.ChatAttachment
import app.maxly.domain.VideoContent
import app.maxly.media.MediaSources
import app.maxly.presentation.chat.ChatFormatter
import app.maxly.presentation.chat.MediaViewerState
import app.maxly.presentation.media.MediaDismissRule
import app.maxly.presentation.media.MediaTimeText
import app.maxly.presentation.media.MediaViewerChrome
import app.maxly.presentation.media.PlaybackSpeed
import app.maxly.presentation.media.SeekTapAccumulator
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

/** Высота полосы управления ролика: подпись встаёт над ней. */
private val VideoControlsHeight = 104.dp

/**
 * Фото и видео сообщения на весь экран, как в Telegram и WhatsApp.
 *
 * - Касание прячет и показывает шапку, подпись, кнопки и системные полосы; у играющего ролика
 *   они уходят сами ([MediaViewerChrome]).
 * - Смахивание вверх или вниз ведёт кадр за пальцем, фон гаснет ([MediaDismissRule]).
 * - Приложение стоит в портрете, а просмотр поворачивается вслед за телефоном.
 */
@kotlin.OptIn(ExperimentalFoundationApi::class)
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
        var scrubbing by remember { mutableStateOf(false) }
        var dismissY by remember { mutableFloatStateOf(0f) }
        var height by remember { mutableFloatStateOf(1f) }
        val scope = rememberCoroutineScope()
        // Поворот фото четвертями по часовой, свой у каждого фото. Счёт не по модулю 4:
        // анимация после четвёртого поворота идёт дальше по часовой, а не крутится назад.
        val turns = remember { mutableStateMapOf<String, Int>() }
        LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { chrome = true } }

        RotationWhileOpen()
        ImmersiveWhenHidden(hidden = !chrome)

        val dismiss = DismissHandlers(
            onDrag = { dismissY = it },
            onEnd = { velocity ->
                if (MediaDismissRule.shouldClose(dismissY, velocity, height)) {
                    onClose()
                } else {
                    val from = dismissY
                    scope.launch { animate(from, 0f, animationSpec = spring(dampingRatio = 0.85f)) { value, _ -> dismissY = value } }
                }
            },
        )

        Box(
            Modifier
                .fillMaxSize()
                .onSizeChanged { height = it.height.toFloat().coerceAtLeast(1f) }
                .background(Color.Black.copy(alpha = MediaDismissRule.backgroundAlpha(dismissY, height))),
        ) {
            HorizontalPager(
                pager,
                Modifier.fillMaxSize().graphicsLayer { translationY = dismissY },
                key = { state.items[it].id },
                userScrollEnabled = zoomedPage != pager.currentPage && !scrubbing,
            ) { page ->
                val active = pager.currentPage == page
                when (val item = state.items[page]) {
                    is ChatAttachment.Photo -> ZoomablePhoto(
                        url = item.photo.url,
                        turns = turns[item.id] ?: 0,
                        active = active,
                        onChrome = { chrome = !chrome },
                        dismiss = dismiss,
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
                        chrome = chrome,
                        onChrome = { chrome = it },
                        onScrubbing = { scrubbing = it },
                        dismiss = dismiss,
                    )
                    else -> Unit
                }
            }
            val current = state.items.getOrNull(pager.currentPage)
            AnimatedVisibility(chrome && dismissY == 0f, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopCenter)) {
                ViewerHeader(
                    state = state,
                    page = pager.currentPage,
                    canRotate = current is ChatAttachment.Photo,
                    onRotate = { if (current != null) turns[current.id] = (turns[current.id] ?: 0) + 1 },
                    onClose = onClose,
                    onSave = onSave,
                    saving = saving,
                )
            }
            if (state.caption.isNotEmpty()) {
                AnimatedVisibility(chrome && dismissY == 0f, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter)) {
                    ViewerCaption(state.caption, bottomInset = if (current is ChatAttachment.Video) VideoControlsHeight else 0.dp)
                }
            }
        }
    }
}

/** Пока просмотр открыт, экран поворачивается вслед за телефоном; закрыли — снова портрет. */
@Composable
private fun RotationWhileOpen() {
    val context = LocalContext.current
    DisposableEffect(context) {
        val activity = context.findActivity()
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_USER
        onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
    }
}

/** Интерфейс спрятан — системные полосы тоже; смахивание от края показывает их на время. */
@Composable
private fun ImmersiveWhenHidden(hidden: Boolean) {
    val view = LocalView.current
    val window = (view.parent as? DialogWindowProvider)?.window
    LaunchedEffect(window, hidden) {
        val target = window ?: return@LaunchedEffect
        val controller = WindowCompat.getInsetsController(target, view)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (hidden) controller.hide(WindowInsetsCompat.Type.systemBars()) else controller.show(WindowInsetsCompat.Type.systemBars())
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** Куда страница сообщает о смахивании: сдвиг кадра и скорость в конце, px и px/с. */
private class DismissHandlers(val onDrag: (Float) -> Unit, val onEnd: (Float) -> Unit)

/** Шапка: назад, кто и когда, «3 из 7», поворот фото и сохранение. */
@Composable
private fun ViewerHeader(
    state: MediaViewerState,
    page: Int,
    canRotate: Boolean,
    onRotate: () -> Unit,
    onClose: () -> Unit,
    onSave: (() -> Unit)?,
    saving: Boolean,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.6f), Color.Transparent)))
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .padding(start = 4.dp, end = 4.dp, top = 4.dp, bottom = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Закрыть", tint = Color.White) }
        Spacer(Modifier.width(4.dp))
        Column(Modifier.weight(1f)) {
            Text(state.authorName.ifEmpty { "Медиа" }, color = Color.White, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val subtitle = listOfNotNull(
                viewerDate(state.timeMs).ifEmpty { null },
                if (state.items.size > 1) "${page + 1} из ${state.items.size}" else null,
            ).joinToString(" · ")
            if (subtitle.isNotEmpty()) {
                Text(subtitle, color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.bodySmall, maxLines = 1)
            }
        }
        if (canRotate) {
            IconButton(onClick = onRotate) { Icon(Icons.Outlined.Rotate90DegreesCw, "Повернуть", tint = Color.White) }
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

/** Подпись внизу: три строки, касание раскрывает целиком. */
@Composable
private fun ViewerCaption(text: String, bottomInset: androidx.compose.ui.unit.Dp) {
    var expanded by remember { mutableStateOf(false) }
    Text(
        text,
        color = Color.White,
        style = MaterialTheme.typography.bodyMedium,
        maxLines = if (expanded) Int.MAX_VALUE else 3,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f))))
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
            .clickable { expanded = !expanded }
            .padding(start = 16.dp, end = 16.dp, top = 28.dp, bottom = 12.dp + bottomInset),
    )
}

private fun viewerDate(timeMs: Long): String {
    if (timeMs <= 0) return ""
    val formatter = ChatFormatter()
    return "${formatter.dayLabel(timeMs, System.currentTimeMillis())}, ${formatter.time(timeMs)}"
}

/**
 * Вертикальное смахивание без зума: кадр едет за пальцем вверх или вниз, отпустили — страница
 * решает, закрыть или вернуть. Горизонтальный жест остаётся пейджеру.
 */
private suspend fun PointerInputScope.detectVerticalDismiss(enabled: () -> Boolean, dismiss: () -> DismissHandlers) {
    val slop = viewConfiguration.touchSlop
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val tracker = VelocityTracker()
        tracker.addPosition(down.uptimeMillis, down.position)
        var total = Offset.Zero
        // 0 — ещё не ясно, 1 — смахивание, 2 — чужой жест.
        var mode = if (enabled()) 0 else 2
        do {
            val event = awaitPointerEvent()
            if (event.changes.size > 1 && mode != 1) mode = 2
            val change = event.changes.first()
            tracker.addPosition(change.uptimeMillis, change.position)
            total += event.calculatePan()
            if (mode == 0 && (abs(total.x) > slop || abs(total.y) > slop)) {
                mode = if (abs(total.y) > abs(total.x)) 1 else 2
            }
            if (mode == 1) {
                dismiss().onDrag(total.y)
                event.changes.forEach { if (it.positionChanged()) it.consume() }
            }
        } while (event.changes.any { it.pressed })
        if (mode == 1) dismiss().onEnd(tracker.calculateVelocity().y)
    }
}

/**
 * Фото с зумом 1…5×. Касание прячет интерфейс, двойное касание приближает к точке в 2,5 раза
 * и обратно. Увеличенное едет за пальцем и не отдаёт жест пейджеру.
 */
@Composable
private fun ZoomablePhoto(
    url: String?,
    turns: Int,
    active: Boolean,
    onChrome: () -> Unit,
    dismiss: DismissHandlers,
    onZoomed: (Boolean) -> Unit,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var imageSize by remember { mutableStateOf(Size.Unspecified) }
    var loaded by remember { mutableStateOf(false) }
    val angle by animateFloatAsState(turns * 90f, label = "rotation")
    val scope = rememberCoroutineScope()
    val chromeToggle by rememberUpdatedState(onChrome)
    val handlers by rememberUpdatedState(dismiss)
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
                    onTap = { chromeToggle() },
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
                // Щипок и сдвиг увеличенного фото.
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.size > 1 || scale > 1.01f) {
                            val next = (scale * event.calculateZoom()).coerceIn(1f, 5f)
                            val pan = event.calculatePan()
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
            }
            .pointerInput(Unit) { detectVerticalDismiss(enabled = { scale <= 1.01f }, dismiss = { handlers }) },
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            model = url,
            contentDescription = "Фото",
            contentScale = ContentScale.Fit,
            onSuccess = {
                imageSize = it.painter.intrinsicSize
                loaded = true
            },
            modifier = Modifier.fillMaxSize().graphicsLayer {
                val fit = sidewaysFit(imageSize, size, turns)
                scaleX = scale * fit
                scaleY = scale * fit
                rotationZ = angle
                translationX = offset.x
                translationY = offset.y
            },
        )
        if (!loaded && url != null) CircularProgressIndicator(color = Color.White)
    }
}

/**
 * Ролик: свой плеер и жесты. Касание — интерфейс, двойное касание у края — ±10 с (подряд —
 * копится), в середине — пауза; удержание — 2×. Внизу полоса с подгруженной частью, время,
 * звук и скорость. Пока ролик грузится — кольцо с долей. Играет только видимая страница.
 */
@OptIn(UnstableApi::class)
@Composable
private fun VideoPage(
    video: VideoContent,
    url: String?,
    userAgent: String,
    active: Boolean,
    chrome: Boolean,
    onChrome: (Boolean) -> Unit,
    onScrubbing: (Boolean) -> Unit,
    dismiss: DismissHandlers,
) {
    val context = LocalContext.current
    var playing by remember { mutableStateOf(false) }
    var wantsPlay by remember { mutableStateOf(false) }
    var ended by remember { mutableStateOf(false) }
    var buffering by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var stopped by remember { mutableStateOf(false) }
    var firstFrame by remember { mutableStateOf(false) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var bufferedMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(0L) }
    var scrubFraction by remember { mutableStateOf<Float?>(null) }
    var rate by remember { mutableFloatStateOf(1f) }
    var muted by remember { mutableStateOf(false) }
    var holding by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var seekBadge by remember { mutableStateOf<SeekTapAccumulator.Seek?>(null) }
    val taps = remember { SeekTapAccumulator() }
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
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) { wantsPlay = playWhenReady }
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING
                ended = state == Player.STATE_ENDED
                if (state == Player.STATE_READY) failed = false
                durationMs = current.duration.coerceAtLeast(0L)
            }
            override fun onRenderedFirstFrame() { firstFrame = true }
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
            positionMs = current.currentPosition.coerceAtLeast(0L)
            bufferedMs = current.bufferedPosition.coerceAtLeast(0L)
            val duration = current.duration
            if (duration > 0) durationMs = duration
            delay(100)
        }
    }
    val playbackStopped = !wantsPlay || ended || failed || stopped
    // Ролик встал — интерфейс нужен, чтобы продолжить.
    LaunchedEffect(active, playbackStopped) { if (active && playbackStopped) onChrome(true) }
    // Играющий ролик через 3 секунды прячет интерфейс.
    LaunchedEffect(active, chrome, playbackStopped, scrubFraction != null, menuOpen) {
        if (!active || !MediaViewerChrome.shouldAutoHide(chrome, !playbackStopped, scrubFraction != null, menuOpen)) return@LaunchedEffect
        delay(MediaViewerChrome.AUTO_HIDE_MS)
        onChrome(false)
    }
    LaunchedEffect(seekBadge) {
        if (seekBadge == null) return@LaunchedEffect
        delay(SeekTapAccumulator.WINDOW_MS)
        seekBadge = null
    }
    LaunchedEffect(chrome) { menuOpen = menuOpen && chrome }

    fun toggle() {
        val current = player ?: return
        when {
            // Читаем плеер, а не снимок состояния: жест запоминает эту функцию до конца ролика.
            current.playerError != null || current.playbackState == Player.STATE_IDLE -> {
                failed = false
                stopped = false
                buffering = true
                current.prepare()
                current.playWhenReady = true
            }
            current.playbackState == Player.STATE_ENDED -> {
                current.seekTo(0)
                current.playWhenReady = true
            }
            current.playWhenReady -> current.pause()
            else -> current.play()
        }
    }
    fun seekTap(forward: Boolean) {
        val current = player ?: return
        val seek = taps.tap(forward, System.currentTimeMillis(), current.currentPosition, current.duration.coerceAtLeast(0L))
        current.seekTo(seek.targetMs)
        positionMs = seek.targetMs
        seekBadge = seek
    }
    val chromeUpdate by rememberUpdatedState(onChrome)
    val chromeVisible by rememberUpdatedState(chrome)
    val handlers by rememberUpdatedState(dismiss)

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (!firstFrame) AsyncImage(video.posterUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
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
                    detectTapGestures(
                        onTap = { point ->
                            // Третье и дальнейшие касания у края, пока перемотка не остыла, копят секунды.
                            val side = SeekTapAccumulator.side(point.x, size.width.toFloat())
                            if (side != null && taps.isActive(System.currentTimeMillis())) seekTap(side) else chromeUpdate(!chromeVisible)
                        },
                        onDoubleTap = { point ->
                            when (val side = SeekTapAccumulator.side(point.x, size.width.toFloat())) {
                                null -> toggle()
                                else -> seekTap(side)
                            }
                        },
                        onLongPress = {
                            player?.let { current ->
                                holding = true
                                if (!current.playWhenReady) current.play()
                                current.setPlaybackSpeed(PlaybackSpeed.HOLD)
                            }
                        },
                        onPress = {
                            tryAwaitRelease()
                            if (holding) {
                                holding = false
                                player?.setPlaybackSpeed(rate)
                            }
                        },
                    )
                }
                .pointerInput(Unit) { detectVerticalDismiss(enabled = { true }, dismiss = { handlers }) },
        )
        LoadingOverlay(
            failed = failed,
            stopped = stopped,
            loading = buffering && !firstFrame && player != null,
            fraction = if (durationMs > 0) bufferedMs.toFloat() / durationMs else null,
            onCancel = {
                player?.stop()
                stopped = true
            },
            onRetry = { toggle() },
        )
        seekBadge?.let { seek ->
            SeekBadge(seek, Modifier.align(if (seek.forward) Alignment.CenterEnd else Alignment.CenterStart).padding(horizontal = 36.dp))
        }
        if (holding) {
            Text(
                "${PlaybackSpeed.label(PlaybackSpeed.HOLD)} ▸▸",
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top))
                    .padding(top = 64.dp)
                    .background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(50))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
        val ready = player != null && !failed && !stopped && !(buffering && !firstFrame)
        AnimatedVisibility(chrome && ready, enter = fadeIn(), exit = fadeOut()) {
            IconButton(
                onClick = { toggle() },
                modifier = Modifier.size(72.dp).background(Color.Black.copy(alpha = 0.4f), CircleShape),
            ) {
                val icon = when {
                    ended -> Icons.Filled.Replay
                    wantsPlay -> Icons.Filled.Pause
                    else -> Icons.Filled.PlayArrow
                }
                Icon(icon, if (wantsPlay) "Пауза" else "Смотреть", tint = Color.White, modifier = Modifier.size(40.dp))
            }
        }
        AnimatedVisibility(chrome && player != null, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter)) {
            VideoControls(
                fraction = scrubFraction ?: if (durationMs > 0) positionMs.toFloat() / durationMs else 0f,
                buffered = if (durationMs > 0) bufferedMs.toFloat() / durationMs else 0f,
                positionMs = scrubFraction?.let { (it * durationMs).toLong() } ?: positionMs,
                durationMs = durationMs,
                playing = wantsPlay && !ended,
                ended = ended,
                muted = muted,
                rate = rate,
                menuOpen = menuOpen,
                onMenu = { menuOpen = it },
                onToggle = { toggle() },
                onMute = {
                    muted = !muted
                    player?.volume = if (muted) 0f else 1f
                },
                onRate = { value ->
                    rate = value
                    player?.setPlaybackSpeed(value)
                    menuOpen = false
                },
                onScrub = { fraction ->
                    if (scrubFraction == null) onScrubbing(true)
                    scrubFraction = fraction
                    if (durationMs > 0) player?.seekTo((durationMs * fraction).toLong())
                },
                onScrubEnd = { fraction ->
                    if (durationMs > 0) {
                        val target = (durationMs * fraction).toLong()
                        player?.seekTo(target)
                        positionMs = target
                    }
                    scrubFraction = null
                    onScrubbing(false)
                },
            )
        }
    }
}

/** Кольцо загрузки с долей и крестиком, или ошибка с «Повторить». */
@Composable
private fun LoadingOverlay(failed: Boolean, stopped: Boolean, loading: Boolean, fraction: Float?, onCancel: () -> Unit, onRetry: () -> Unit) {
    when {
        failed || stopped -> Column(
            Modifier.background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(16.dp)).padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(if (failed) "Видео не воспроизводится" else "Загрузка остановлена", color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium)
            TextButton(onClick = onRetry) { Text("Повторить", color = Color.White) }
        }
        loading -> Column(
            Modifier.background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(18.dp)).padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(60.dp), contentAlignment = Alignment.Center) {
                if (fraction != null && fraction > 0f) {
                    CircularProgressIndicator(
                        progress = { fraction.coerceIn(0.02f, 1f) },
                        modifier = Modifier.size(60.dp),
                        color = Color.White,
                        trackColor = Color.White.copy(alpha = 0.25f),
                        strokeWidth = 4.dp,
                    )
                } else {
                    CircularProgressIndicator(Modifier.size(60.dp), color = Color.White, strokeWidth = 4.dp)
                }
                IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, "Отменить загрузку", tint = Color.White) }
            }
            if (fraction != null && fraction > 0f) {
                Text(MediaTimeText.download(fraction), color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
            }
        }
    }
}

/** «‹‹ 20 с» у левого края или «20 с ››» у правого. */
@Composable
private fun SeekBadge(seek: SeekTapAccumulator.Seek, modifier: Modifier) {
    Column(
        modifier.size(84.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(if (seek.forward) Icons.Filled.FastForward else Icons.Filled.FastRewind, null, tint = Color.White, modifier = Modifier.size(28.dp))
        Text("${seek.totalSeconds} с", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Полоса ролика внизу: перемотка с подгруженной частью, пауза, время, звук и скорость. */
@Composable
private fun VideoControls(
    fraction: Float,
    buffered: Float,
    positionMs: Long,
    durationMs: Long,
    playing: Boolean,
    ended: Boolean,
    muted: Boolean,
    rate: Float,
    menuOpen: Boolean,
    onMenu: (Boolean) -> Unit,
    onToggle: () -> Unit,
    onMute: () -> Unit,
    onRate: (Float) -> Unit,
    onScrub: (Float) -> Unit,
    onScrubEnd: (Float) -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
            .padding(start = 12.dp, end = 12.dp, top = 16.dp, bottom = 4.dp),
    ) {
        Scrubber(fraction, buffered, enabled = durationMs > 0, onScrub = onScrub, onScrubEnd = onScrubEnd)
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onToggle) {
                val icon = when {
                    ended -> Icons.Filled.Replay
                    playing -> Icons.Filled.Pause
                    else -> Icons.Filled.PlayArrow
                }
                Icon(icon, if (playing) "Пауза" else "Смотреть", tint = Color.White)
            }
            Text(
                "${MediaTimeText.clock(positionMs)} / ${if (durationMs > 0) MediaTimeText.clock(durationMs) else "–:––"}",
                color = Color.White.copy(alpha = 0.85f),
                fontSize = 12.sp,
            )
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onMute) {
                Icon(
                    if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                    if (muted) "Включить звук" else "Выключить звук",
                    tint = Color.White,
                )
            }
            Box {
                TextButton(onClick = { onMenu(true) }) {
                    Text(PlaybackSpeed.label(rate), color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { onMenu(false) }) {
                    PlaybackSpeed.options.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(PlaybackSpeed.label(option)) },
                            onClick = { onRate(option) },
                            trailingIcon = if (option == rate) {
                                { Icon(Icons.Filled.Check, null) }
                            } else null,
                        )
                    }
                }
            }
        }
    }
}

/**
 * Полоса перемотки: сыграно — белым, подгружено — светлее, остальное — тускло. Палец ведёт
 * ползунок, кадр меняется вслед.
 */
@Composable
private fun Scrubber(fraction: Float, buffered: Float, enabled: Boolean, onScrub: (Float) -> Unit, onScrubEnd: (Float) -> Unit) {
    var active by remember { mutableStateOf(false) }
    val scrub by rememberUpdatedState(onScrub)
    val end by rememberUpdatedState(onScrubEnd)
    val isEnabled by rememberUpdatedState(enabled)
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(28.dp)
            .alpha(if (enabled) 1f else 0.5f)
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    if (!isEnabled) return@awaitEachGesture
                    down.consume()
                    active = true
                    var last = (down.position.x / size.width).coerceIn(0f, 1f)
                    scrub(last)
                    do {
                        val event = awaitPointerEvent()
                        val change = event.changes.first()
                        if (change.positionChanged()) {
                            last = (change.position.x / size.width).coerceIn(0f, 1f)
                            scrub(last)
                        }
                        change.consume()
                    } while (event.changes.any { it.pressed })
                    active = false
                    end(last)
                }
            },
    ) {
        val track = if (active) 6.dp.toPx() else 4.dp.toPx()
        val top = (size.height - track) / 2
        val radius = CornerRadius(track / 2)
        drawRoundRect(Color.White.copy(alpha = 0.22f), Offset(0f, top), Size(size.width, track), radius)
        drawRoundRect(Color.White.copy(alpha = 0.45f), Offset(0f, top), Size(size.width * buffered.coerceIn(0f, 1f), track), radius)
        val played = size.width * fraction.coerceIn(0f, 1f)
        drawRoundRect(Color.White, Offset(0f, top), Size(played, track), radius)
        drawCircle(Color.White, radius = if (active) 9.dp.toPx() else 6.dp.toPx(), center = Offset(played, size.height / 2))
    }
}

/**
 * Во сколько раз уменьшить фото, повёрнутое на бок ([turns] нечётно), чтобы оно влезло в
 * [box]: вписанная картинка после поворота меняет ширину с высотой. Ровно стоящее — без изменений.
 */
internal fun sidewaysFit(image: Size, box: Size, turns: Int): Float {
    if (turns % 2 == 0 || image == Size.Unspecified || image.width <= 0f || image.height <= 0f || box.width <= 0f || box.height <= 0f) return 1f
    val fitted = minOf(box.width / image.width, box.height / image.height)
    val width = image.width * fitted
    val height = image.height * fitted
    return minOf(box.width / height, box.height / width, 1f)
}
