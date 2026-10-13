package app.maxly.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Rotate90DegreesCw
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.isCtrlPressed
import androidx.compose.ui.input.pointer.isMetaPressed
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.WindowPlacement
import app.maxly.domain.ChatAttachment
import app.maxly.domain.VideoContent
import app.maxly.media.DesktopVideo
import app.maxly.media.DesktopVideoPlayer
import app.maxly.platform.BackHandler
import app.maxly.platform.LocalMainWindowState
import app.maxly.presentation.chat.ChatFormatter
import app.maxly.presentation.chat.MediaViewerState
import app.maxly.presentation.media.MediaTimeText
import app.maxly.presentation.media.MediaViewerChrome
import app.maxly.presentation.media.SeekTapAccumulator
import app.maxly.ui.keys.HotkeyAction
import app.maxly.ui.keys.HotkeyHandler
import app.maxly.ui.media.VideoFrame
import app.maxly.ui.media.rememberVideoPlayer
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import coil3.size.Size
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import app.maxly.presentation.media.ImageRequests
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.outlined.ContentCopy
import app.maxly.ui.media.MiniPlayer
import java.awt.Point
import java.awt.Toolkit
import java.awt.image.BufferedImage

/** Курсор-невидимка: у играющего ролика он прячется вместе с панелью, пока мышь стоит. */
private val HiddenCursor: PointerIcon by lazy {
    PointerIcon(Toolkit.getDefaultToolkit().createCustomCursor(BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB), Point(0, 0), "hidden"))
}

/** Что открытый ролик даёт клавишам просмотра. */
private class VideoKeys(
    val toggle: () -> Unit,
    val seek: (forward: Boolean) -> Unit,
    val mute: () -> Unit,
    val volume: (up: Boolean) -> Unit,
    val pictureInPicture: () -> Unit,
)

/**
 * Фото и видео сообщения на весь экран окна, как в Telegram Desktop.
 *
 * - Мышь двинулась — шапка, стрелки и панель видны; у играющего ролика они и курсор прячутся,
 *   когда мышь постоит ([MediaViewerChrome.AUTO_HIDE_MS]) и не над панелью.
 * - Клавиши: ←/→ — соседнее, Пробел/K — пауза, J/L — ±10 с, ↑/↓ — громкость, M — звук,
 *   F — во весь экран, R — повернуть, Ctrl+S — сохранить, Esc — из полного экрана, затем закрыть.
 * - Фото: Ctrl+колесо — увеличение к курсору, колесо у увеличенного — сдвиг, перетаскивание —
 *   сдвиг, двойной щелчок — 2,5× к точке. Видео: щелчок — пауза, двойной — во весь экран.
 */
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
    /** Скопировать открытое фото или видео в буфер обмена файлом. */
    onCopy: (() -> Unit)? = null,
    /** «Перейти к сообщению»: просмотр закрывается, лента едет к сообщению. */
    onShowInChat: (() -> Unit)? = null,
) {
    // Просмотр проявляется с лёгким приближением и так же гаснет при закрытии.
    val shown = remember { Animatable(0f) }
    val closeScope = rememberCoroutineScope()
    var closing by remember { mutableStateOf(false) }
    fun close(then: (() -> Unit)? = null) {
        if (closing) return
        closing = true
        closeScope.launch {
            shown.animateTo(0f, tween(150))
            onClose()
            then?.invoke()
        }
    }
    Dialog(onDismissRequest = { close() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        LaunchedEffect(Unit) { shown.animateTo(1f, tween(180, easing = FastOutSlowInEasing)) }
        val window = LocalMainWindowState.current
        // Прежнее положение окна, пока просмотр развернул его во весь экран.
        var restore by remember { mutableStateOf<WindowPlacement?>(null) }
        val fullscreen = restore != null
        fun setFullscreen(on: Boolean) {
            val target = window ?: return
            if (on && restore == null) {
                restore = target.placement
                target.placement = WindowPlacement.Fullscreen
            } else if (!on) {
                restore?.let { target.placement = it }
                restore = null
            }
        }
        DisposableEffect(Unit) { onDispose { restore?.let { window?.placement = it } } }
        BackHandler { if (fullscreen) setFullscreen(false) else close() }

        val pager = rememberPagerState(initialPage = state.index) { state.items.size }
        LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect(onPage) }
        val scope = rememberCoroutineScope()
        var chrome by remember { mutableStateOf(true) }
        var lastMove by remember { mutableLongStateOf(0L) }
        var zoomed by remember { mutableStateOf(false) }
        var scrubbing by remember { mutableStateOf(false) }
        var overControls by remember { mutableStateOf(false) }
        var videoPlaying by remember { mutableStateOf(false) }
        var videoKeys by remember { mutableStateOf<VideoKeys?>(null) }
        // Поворот фото четвертями по часовой, свой у каждого фото. Счёт не по модулю 4:
        // анимация после четвёртого поворота идёт дальше по часовой, а не крутится назад.
        val turns = remember { mutableStateMapOf<String, Int>() }
        val step: (Boolean) -> Unit = { forward ->
            val target = pager.currentPage + if (forward) 1 else -1
            if (target in state.items.indices) scope.launch { pager.animateScrollToPage(target) }
        }
        LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { chrome = true } }
        // Играющий ролик прячет панель и курсор, когда мышь постоит.
        LaunchedEffect(lastMove, chrome, videoPlaying, scrubbing, overControls) {
            if (!MediaViewerChrome.shouldAutoHide(chrome, videoPlaying, scrubbing, overControls)) return@LaunchedEffect
            delay(MediaViewerChrome.AUTO_HIDE_MS)
            chrome = false
        }
        // Остальные сочетания (переход по чатам и прочее) под открытым просмотром не срабатывают,
        // кроме выхода из приложения.
        HotkeyHandler { hotkey ->
            when (hotkey.action) {
                HotkeyAction.VIEWER_PREVIOUS -> true.also { step(false) }
                HotkeyAction.VIEWER_NEXT -> true.also { step(true) }
                HotkeyAction.ROTATE -> {
                    val photo = state.items.getOrNull(pager.currentPage) as? ChatAttachment.Photo
                    if (photo != null) turns[photo.id] = (turns[photo.id] ?: 0) + 1
                    true
                }
                HotkeyAction.SAVE -> true.also { if (!saving) onSave?.invoke() }
                HotkeyAction.VIEWER_PAUSE -> true.also {
                    val keys = videoKeys
                    if (keys != null) keys.toggle() else chrome = !chrome
                }
                HotkeyAction.VIEWER_SEEK_BACK -> true.also { videoKeys?.seek?.invoke(false); chrome = true }
                HotkeyAction.VIEWER_SEEK_FORWARD -> true.also { videoKeys?.seek?.invoke(true); chrome = true }
                HotkeyAction.VIEWER_MUTE -> true.also { videoKeys?.mute?.invoke(); chrome = true }
                HotkeyAction.VIEWER_VOLUME_UP -> true.also { videoKeys?.volume?.invoke(true); chrome = true }
                HotkeyAction.VIEWER_VOLUME_DOWN -> true.also { videoKeys?.volume?.invoke(false); chrome = true }
                HotkeyAction.VIEWER_FULLSCREEN -> true.also { setFullscreen(!fullscreen) }
                HotkeyAction.VIEWER_PIP -> true.also { videoKeys?.pictureInPicture?.invoke() }
                HotkeyAction.QUIT -> false
                else -> true
            }
        }
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = shown.value }
                .background(Color.Black)
                .pointerHoverIcon(if (chrome) PointerIcon.Default else HiddenCursor)
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            if (event.type == PointerEventType.Move) {
                                lastMove = System.currentTimeMillis()
                                chrome = true
                            }
                        }
                    }
                },
        ) {
            HorizontalPager(
                pager,
                Modifier.fillMaxSize().graphicsLayer {
                    val scale = 0.94f + 0.06f * shown.value
                    scaleX = scale
                    scaleY = scale
                },
                key = { state.items[it].id },
                userScrollEnabled = !zoomed && !scrubbing,
            ) { page ->
                val active = pager.currentPage == page
                when (val item = state.items[page]) {
                    is ChatAttachment.Photo -> ZoomablePhoto(
                        item.photo.url,
                        turns[item.id] ?: 0,
                        onChrome = { chrome = !chrome },
                        onZoomed = { zoomed = it },
                    )
                    is ChatAttachment.Video -> VideoPage(
                        item.video,
                        state.videoUrls[item.id],
                        userAgent,
                        active = active,
                        chrome = chrome,
                        fullscreen = fullscreen,
                        onFullscreen = { setFullscreen(!fullscreen) },
                        onPlaying = { if (active) videoPlaying = it },
                        onScrubbing = { scrubbing = it },
                        onOverControls = { overControls = it },
                        onBind = { keys ->
                            if (active) {
                                videoKeys = keys
                                if (keys == null) videoPlaying = false
                            }
                        },
                        // Ролик уходит в маленькое окно поверх всех окон, просмотр закрывается.
                        onPictureInPicture = { clip -> close(then = { MiniPlayer.show(clip.copy(title = state.authorName)) }) },
                    )
                    else -> Unit
                }
            }
            val current = state.items.getOrNull(pager.currentPage)
            AnimatedVisibility(chrome, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopCenter)) {
                ViewerHeader(
                    state = state,
                    page = pager.currentPage,
                    canRotate = current is ChatAttachment.Photo,
                    onRotate = { if (current != null) turns[current.id] = (turns[current.id] ?: 0) + 1 },
                    fullscreen = fullscreen,
                    onFullscreen = if (window != null) ({ setFullscreen(!fullscreen) }) else null,
                    onClose = { close() },
                    onSave = onSave,
                    saving = saving,
                    onCopy = onCopy,
                    onShowInChat = onShowInChat?.let { show -> { close(then = show) } },
                )
            }
            if (state.items.size > 1) {
                AnimatedVisibility(chrome && pager.currentPage > 0, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.CenterStart)) {
                    SideArrow(forward = false) { step(false) }
                }
                AnimatedVisibility(chrome && pager.currentPage < state.items.lastIndex, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.CenterEnd)) {
                    SideArrow(forward = true) { step(true) }
                }
            }
            if (state.caption.isNotEmpty() || state.items.size > 1) {
                AnimatedVisibility(chrome, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter)) {
                    Column(
                        Modifier.padding(bottom = if (current is ChatAttachment.Video) 92.dp else 20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (state.caption.isNotEmpty()) {
                            Text(
                                state.caption,
                                color = Color.White,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 4,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier
                                    .widthIn(max = 720.dp)
                                    .background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
                                    .padding(horizontal = 14.dp, vertical = 8.dp),
                            )
                        }
                        if (state.items.size > 1) {
                            ThumbnailStrip(state.items, pager.currentPage) { index -> scope.launch { pager.animateScrollToPage(index) } }
                        }
                    }
                }
            }
        }
    }
}

/** Лента миниатюр альбома: открытая — шире и в рамке, щелчок открывает другую. */
@Composable
private fun ThumbnailStrip(items: List<ChatAttachment>, page: Int, onSelect: (Int) -> Unit) {
    val list = rememberLazyListState()
    val density = LocalDensity.current
    // Открытая миниатюра — посередине ленты.
    LaunchedEffect(page) {
        val viewport = list.layoutInfo.viewportSize.width
        val item = with(density) { 52.dp.roundToPx() }
        list.animateScrollToItem(page, -((viewport - item) / 2).coerceAtLeast(0))
    }
    LazyRow(
        state = list,
        modifier = Modifier.widthIn(max = 720.dp).height(52.dp),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        itemsIndexed(items, key = { _, item -> item.id }) { index, item ->
            val selected = index == page
            val width by animateDpAsState(if (selected) 52.dp else 36.dp, label = "thumb")
            val url = when (item) {
                is ChatAttachment.Photo -> item.photo.url
                is ChatAttachment.Video -> item.video.posterUrl
                else -> null
            }
            Box(
                Modifier
                    .padding(horizontal = if (selected) 4.dp else 0.dp)
                    .size(width, 52.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White.copy(alpha = 0.12f))
                    .then(if (selected) Modifier.border(2.dp, Color.White, RoundedCornerShape(6.dp)) else Modifier)
                    .alpha(if (selected) 1f else 0.6f)
                    .pointerHoverIcon(PointerIcon.Hand)
                    .clickable { onSelect(index) },
                contentAlignment = Alignment.Center,
            ) {
                AsyncImage(ImageRequests.width(url, 72f, density.density), if (item is ChatAttachment.Video) "Видео" else "Фото", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                if (item is ChatAttachment.Video) Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
        }
    }
}

/** Шапка: назад, кто и когда, «3 из 7», поворот, полный экран и сохранение. */
@Composable
private fun ViewerHeader(
    state: MediaViewerState,
    page: Int,
    canRotate: Boolean,
    onRotate: () -> Unit,
    fullscreen: Boolean,
    onFullscreen: (() -> Unit)?,
    onClose: () -> Unit,
    onSave: (() -> Unit)?,
    saving: Boolean,
    onCopy: (() -> Unit)?,
    onShowInChat: (() -> Unit)?,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.6f), Color.Transparent)))
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
            if (subtitle.isNotEmpty()) Text(subtitle, color = Color.White.copy(alpha = 0.7f), style = MaterialTheme.typography.bodySmall, maxLines = 1)
        }
        if (canRotate) {
            IconButton(onClick = onRotate) { Icon(Icons.Outlined.Rotate90DegreesCw, "Повернуть (R)", tint = Color.White) }
        }
        if (onFullscreen != null) {
            IconButton(onClick = onFullscreen) {
                Icon(if (fullscreen) Icons.Filled.FullscreenExit else Icons.Filled.Fullscreen, if (fullscreen) "Свернуть (F)" else "Во весь экран (F)", tint = Color.White)
            }
        }
        if (onShowInChat != null) {
            IconButton(onClick = onShowInChat) { Icon(Icons.AutoMirrored.Outlined.Chat, "Перейти к сообщению", tint = Color.White) }
        }
        if (saving) {
            CircularProgressIndicator(Modifier.padding(12.dp).size(24.dp), color = Color.White, strokeWidth = 2.dp)
        } else {
            if (onCopy != null) {
                IconButton(onClick = onCopy) { Icon(Icons.Outlined.ContentCopy, "Копировать файл", tint = Color.White) }
            }
            if (onSave != null) {
                IconButton(onClick = onSave) { Icon(Icons.Outlined.Download, "Сохранить в галерею", tint = Color.White) }
            }
        }
    }
}

/** Стрелка к соседнему фото или видео у края окна. */
@Composable
private fun SideArrow(forward: Boolean, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.padding(horizontal = 12.dp).size(48.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape),
    ) {
        Icon(
            if (forward) Icons.AutoMirrored.Filled.KeyboardArrowRight else Icons.AutoMirrored.Filled.KeyboardArrowLeft,
            if (forward) "Следующее" else "Предыдущее",
            tint = Color.White,
        )
    }
}

private fun viewerDate(timeMs: Long): String {
    if (timeMs <= 0) return ""
    val formatter = ChatFormatter()
    return "${formatter.dayLabel(timeMs, System.currentTimeMillis())}, ${formatter.time(timeMs)}"
}

/**
 * Фото с зумом 1…5×: Ctrl+колесо (и щипок на тачпаде) — к курсору, колесо у увеличенного —
 * сдвиг, перетаскивание увеличенного — сдвиг, двойной щелчок — 2,5× к точке и обратно.
 * [turns] — поворот четвертями по часовой: повёрнутое на бок фото уменьшается, чтобы влезть.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
private fun ZoomablePhoto(
    url: String?,
    turns: Int,
    onChrome: () -> Unit,
    onZoomed: (Boolean) -> Unit,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var imageSize by remember { mutableStateOf(androidx.compose.ui.geometry.Size.Unspecified) }
    var loaded by remember { mutableStateOf(false) }
    val angle by animateFloatAsState(turns * 90f, label = "rotation")
    val chromeToggle by rememberUpdatedState(onChrome)
    // Повернули — зум и сдвиг сначала.
    LaunchedEffect(turns) {
        scale = 1f
        offset = Offset.Zero
    }
    LaunchedEffect(scale) { onZoomed(scale > 1.01f) }
    DisposableEffect(Unit) { onDispose { onZoomed(false) } }
    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        if (event.type != PointerEventType.Scroll) continue
                        val change = event.changes.firstOrNull() ?: continue
                        val delta = change.scrollDelta
                        val modifiers = event.keyboardModifiers
                        if (modifiers.isCtrlPressed || modifiers.isMetaPressed) {
                            if (delta.y == 0f) continue
                            val next = (scale * if (delta.y < 0f) 1.15f else 1f / 1.15f).coerceIn(1f, 5f)
                            val factor = next / scale
                            // Точка под курсором остаётся под ним.
                            val cursor = change.position - Offset(size.width / 2f, size.height / 2f)
                            val moved = cursor - (cursor - offset) * factor
                            offset = clampOffset(moved, next, size.width.toFloat(), size.height.toFloat())
                            scale = next
                            change.consume()
                        } else if (scale > 1.01f) {
                            val moved = offset - Offset(delta.x, delta.y) * 48f
                            offset = clampOffset(moved, scale, size.width.toFloat(), size.height.toFloat())
                            change.consume()
                        }
                    }
                }
            }
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { chromeToggle() },
                    onDoubleTap = { point ->
                        if (scale > 1f) {
                            scale = 1f
                            offset = Offset.Zero
                        } else {
                            val center = Offset(size.width / 2f, size.height / 2f)
                            scale = 2.5f
                            offset = clampOffset((center - point) * 1.5f, 2.5f, size.width.toFloat(), size.height.toFloat())
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
                        // Без увеличения мышь листает пейджер.
                        if (event.changes.size > 1 || scale > 1f) {
                            val next = (scale * zoom).coerceIn(1f, 5f)
                            offset = if (next == 1f) Offset.Zero else clampOffset(offset + pan, next, size.width.toFloat(), size.height.toFloat())
                            scale = next
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        // Оригинал декодируется целиком, а не под размер окна: иначе приближение растягивает
        // уменьшенную копию и фото мылится.
        val context = LocalPlatformContext.current
        val request = remember(url) { ImageRequest.Builder(context).data(url).size(Size.ORIGINAL).build() }
        AsyncImage(
            model = request,
            filterQuality = FilterQuality.High,
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

/** Сдвиг увеличенного фото не дальше его краёв. */
private fun clampOffset(offset: Offset, scale: Float, width: Float, height: Float): Offset {
    if (scale <= 1f) return Offset.Zero
    val limitX = width * (scale - 1) / 2
    val limitY = height * (scale - 1) / 2
    return Offset(offset.x.coerceIn(-limitX, limitX), offset.y.coerceIn(-limitY, limitY))
}

/**
 * Видео играет здесь же, встроенным проигрывателем: щелчок — пауза, двойной — во весь экран.
 * Пока ролик качается — кольцо с долей и крестиком. Внизу перемотка, время, звук с громкостью.
 * Играет только видимая страница. Без ffmpeg ролик открывается системным проигрывателем.
 */
@Composable
private fun VideoPage(
    video: VideoContent,
    url: String?,
    userAgent: String,
    active: Boolean,
    chrome: Boolean,
    fullscreen: Boolean,
    onFullscreen: () -> Unit,
    onPlaying: (Boolean) -> Unit,
    onScrubbing: (Boolean) -> Unit,
    onOverControls: (Boolean) -> Unit,
    onBind: (VideoKeys?) -> Unit,
    onPictureInPicture: (MiniPlayer.Clip) -> Unit,
) {
    val player = rememberVideoPlayer()
    val state by player.state.collectAsState()
    var opening by remember { mutableStateOf(false) }
    var stopped by remember { mutableStateOf(false) }
    var scrubFraction by remember { mutableStateOf<Float?>(null) }
    var seekBadge by remember { mutableStateOf<SeekTapAccumulator.Seek?>(null) }
    val taps = remember { SeekTapAccumulator() }
    val scope = rememberCoroutineScope()
    LaunchedEffect(url) { if (url != null) player.open(url, userAgent, autoplay = active) }
    LaunchedEffect(active) { if (!active) player.pause() }
    LaunchedEffect(active, state.isPlaying) { if (active) onPlaying(state.isPlaying) }
    LaunchedEffect(seekBadge) {
        if (seekBadge == null) return@LaunchedEffect
        delay(SeekTapAccumulator.WINDOW_MS)
        seekBadge = null
    }
    fun seek(forward: Boolean) {
        val now = player.state.value
        val result = taps.tap(forward, System.currentTimeMillis(), now.positionMs, now.durationMs)
        player.seekTo(result.targetMs)
        seekBadge = result
    }
    fun volume(up: Boolean) {
        val now = player.state.value
        player.setVolume((now.volume + if (up) 0.1f else -0.1f).coerceIn(0f, 1f))
    }
    DisposableEffect(active, player) {
        if (active) {
            onBind(
                VideoKeys(
                    toggle = { player.toggle() },
                    seek = ::seek,
                    mute = { player.setMuted(!player.state.value.muted) },
                    volume = ::volume,
                    pictureInPicture = { if (url != null) onPictureInPicture(MiniPlayer.Clip(url, userAgent, player.state.value.positionMs, "")) },
                ),
            )
        }
        onDispose { if (active) onBind(null) }
    }
    val retry = {
        stopped = false
        if (url != null) player.open(url, userAgent, autoplay = true)
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (state.frame == null) AsyncImage(video.posterUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        VideoFrame(
            state,
            Modifier.fillMaxSize().pointerInput(player) {
                detectTapGestures(
                    onTap = { player.toggle() },
                    onDoubleTap = { onFullscreen() },
                )
            },
        )
        val downloading = state.downloading
        when {
            stopped -> Column(
                Modifier.background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(16.dp)).padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("Загрузка остановлена", color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = retry) { Text("Повторить", color = Color.White) }
            }
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
            downloading != null -> DownloadRing(downloading) {
                player.release()
                stopped = true
            }
            url == null || (state.isBuffering && state.frame == null) -> CircularProgressIndicator(color = Color.White)
            !state.isPlaying && !state.isBuffering -> Icon(
                if (state.ended) Icons.Filled.Replay else Icons.Filled.PlayArrow,
                null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(72.dp).background(Color.Black.copy(alpha = 0.35f), CircleShape).padding(8.dp),
            )
        }
        seekBadge?.let { seek ->
            Column(
                Modifier
                    .align(if (seek.forward) Alignment.CenterEnd else Alignment.CenterStart)
                    .padding(horizontal = 96.dp)
                    .size(84.dp)
                    .background(Color.Black.copy(alpha = 0.35f), CircleShape),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(if (seek.forward) Icons.Filled.FastForward else Icons.Filled.FastRewind, null, tint = Color.White, modifier = Modifier.size(28.dp))
                Text("${seek.totalSeconds} с", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (!state.failed && !stopped && url != null) {
            AnimatedVisibility(chrome, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter)) {
                VideoBar(
                    player = player,
                    state = state,
                    scrubFraction = scrubFraction,
                    fullscreen = fullscreen,
                    onFullscreen = onFullscreen,
                    onPictureInPicture = {
                        if (url != null) onPictureInPicture(MiniPlayer.Clip(url, userAgent, player.state.value.positionMs, ""))
                    },
                    onHover = onOverControls,
                    onScrub = { fraction ->
                        if (scrubFraction == null) onScrubbing(true)
                        scrubFraction = fraction
                    },
                    onScrubEnd = { fraction ->
                        player.seek(fraction)
                        scrubFraction = null
                        onScrubbing(false)
                    },
                )
            }
        }
    }
}

/** Кольцо загрузки ролика с долей и крестиком отмены. */
@Composable
private fun DownloadRing(fraction: Float, onCancel: () -> Unit) {
    Column(
        Modifier.background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(18.dp)).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(60.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                progress = { fraction.coerceIn(0.02f, 1f) },
                modifier = Modifier.size(60.dp),
                color = Color.White,
                trackColor = Color.White.copy(alpha = 0.25f),
                strokeWidth = 4.dp,
            )
            IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, "Отменить загрузку", tint = Color.White) }
        }
        Text(MediaTimeText.download(fraction), color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
    }
}

/**
 * Панель ролика: перемотка (во время перетаскивания кадр не дёргается, перемотка — на отпускании),
 * пауза, время, звук с громкостью и полный экран. Пока мышь над панелью, она не прячется.
 */
@Composable
private fun VideoBar(
    player: DesktopVideoPlayer,
    state: DesktopVideoPlayer.State,
    scrubFraction: Float?,
    fullscreen: Boolean,
    onFullscreen: () -> Unit,
    onPictureInPicture: () -> Unit,
    onHover: (Boolean) -> Unit,
    onScrub: (Float) -> Unit,
    onScrubEnd: (Float) -> Unit,
) {
    val hover = remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    LaunchedEffect(hovered) { onHover(hovered) }
    DisposableEffect(Unit) { onDispose { onHover(false) } }
    val positionMs = scrubFraction?.let { (it * state.durationMs).toLong() } ?: state.positionMs
    Column(
        Modifier
            .fillMaxWidth()
            .hoverable(hover)
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
            .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 6.dp),
    ) {
        Scrubber(
            fraction = scrubFraction ?: state.progress,
            // Ролик играет из скачанного файла: подгружен целиком.
            buffered = if (state.downloading == null && state.durationMs > 0) 1f else 0f,
            enabled = state.durationMs > 0,
            onScrub = onScrub,
            onScrubEnd = onScrubEnd,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = player::toggle) {
                val icon = when {
                    state.ended -> Icons.Filled.Replay
                    state.isPlaying -> Icons.Filled.Pause
                    else -> Icons.Filled.PlayArrow
                }
                Icon(icon, if (state.isPlaying) "Пауза (K)" else "Смотреть (K)", tint = Color.White)
            }
            Text(
                "${MediaTimeText.clock(positionMs)} / ${if (state.durationMs > 0) MediaTimeText.clock(state.durationMs) else "–:––"}",
                color = Color.White.copy(alpha = 0.85f),
                fontSize = 12.sp,
            )
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { player.setMuted(!state.muted) }) {
                val silent = state.muted || state.volume <= 0f
                Icon(
                    if (silent) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                    if (silent) "Включить звук (M)" else "Выключить звук (M)",
                    tint = Color.White,
                )
            }
            Scrubber(
                fraction = if (state.muted) 0f else state.volume,
                buffered = 0f,
                enabled = true,
                onScrub = player::setVolume,
                onScrubEnd = player::setVolume,
                modifier = Modifier.width(96.dp),
            )
            Spacer(Modifier.width(8.dp))
            IconButton(onClick = onPictureInPicture) {
                Icon(Icons.Filled.PictureInPictureAlt, "Картинка в картинке (P)", tint = Color.White)
            }
            IconButton(onClick = onFullscreen) {
                Icon(if (fullscreen) Icons.Filled.FullscreenExit else Icons.Filled.Fullscreen, if (fullscreen) "Свернуть (F)" else "Во весь экран (F)", tint = Color.White)
            }
        }
    }
}

/**
 * Полоса: сыграно — белым, подгружено — светлее, остальное — тускло. Нажатие и перетаскивание
 * ведут ползунок; под мышью полоса толще.
 */
@Composable
private fun Scrubber(
    fraction: Float,
    buffered: Float,
    enabled: Boolean,
    onScrub: (Float) -> Unit,
    onScrubEnd: (Float) -> Unit,
    modifier: Modifier = Modifier.fillMaxWidth(),
) {
    var dragging by remember { mutableStateOf(false) }
    val hover = remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    val scrub by rememberUpdatedState(onScrub)
    val end by rememberUpdatedState(onScrubEnd)
    val isEnabled by rememberUpdatedState(enabled)
    val active = dragging || hovered
    Canvas(
        modifier
            .height(24.dp)
            .alpha(if (enabled) 1f else 0.5f)
            .hoverable(hover)
            .pointerHoverIcon(PointerIcon.Hand)
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    if (!isEnabled) return@awaitEachGesture
                    down.consume()
                    dragging = true
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
                    dragging = false
                    end(last)
                }
            },
    ) {
        val track = if (active) 6.dp.toPx() else 4.dp.toPx()
        val top = (size.height - track) / 2
        val radius = CornerRadius(track / 2)
        drawRoundRect(Color.White.copy(alpha = 0.22f), Offset(0f, top), androidx.compose.ui.geometry.Size(size.width, track), radius)
        drawRoundRect(Color.White.copy(alpha = 0.45f), Offset(0f, top), androidx.compose.ui.geometry.Size(size.width * buffered.coerceIn(0f, 1f), track), radius)
        val played = size.width * fraction.coerceIn(0f, 1f)
        drawRoundRect(Color.White, Offset(0f, top), androidx.compose.ui.geometry.Size(played, track), radius)
        if (active) drawCircle(Color.White, radius = 7.dp.toPx(), center = Offset(played, size.height / 2))
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
