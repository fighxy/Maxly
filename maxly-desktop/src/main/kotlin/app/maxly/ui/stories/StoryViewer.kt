package app.maxly.ui.stories

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.maxly.data.ComplaintChoice
import app.maxly.domain.StoryRing
import app.maxly.platform.BackHandler
import app.maxly.presentation.stories.StoryText
import app.maxly.presentation.stories.StoryViewerActions
import app.maxly.presentation.stories.StoryViewerState
import app.maxly.ui.components.Avatar
import app.maxly.ui.keys.HotkeyAction
import app.maxly.ui.keys.HotkeyHandler
import app.maxly.ui.media.VideoFrame
import app.maxly.ui.media.rememberVideoPlayer
import coil3.compose.AsyncImage

private const val PHOTO_DURATION_MS = 5_000

/**
 * Просмотр историй на компьютере, как в Max: карточка истории по центру поверх затемнённого окна,
 * по бокам — соседние авторы (щелчок открывает их), стрелки — к соседней истории. Над карточкой —
 * автор, время, пауза, звук и «⋯» (профиль, скрыть истории автора, скачать, пожаловаться; у своей —
 * удалить); под ней — «Ответить» и сердечко. Щелчок по левой трети — назад, по остальной — вперёд;
 * пока нажато, пишется ответ или открыто меню, история стоит.
 */
@Composable
fun StoryViewer(
    viewer: StoryViewerState,
    userAgent: String,
    actions: StoryViewerActions,
    busy: Boolean = false,
    reportReasons: List<ComplaintChoice>? = null,
) {
    Dialog(onDismissRequest = actions.onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BackHandler(onBack = actions.onClose)
        val act by rememberUpdatedState(actions)
        var pressed by remember { mutableStateOf(false) }
        var paused by remember { mutableStateOf(false) }
        var muted by remember { mutableStateOf(false) }
        var typing by remember { mutableStateOf(false) }
        var menu by remember { mutableStateOf(false) }
        var confirmDelete by remember { mutableStateOf(false) }
        var reply by remember(viewer.epoch) { mutableStateOf("") }
        val story = viewer.story
        val media = story?.media
        var ready by remember(viewer.epoch) { mutableStateOf(false) }
        val player = rememberVideoPlayer()
        val video by player.state.collectAsState()
        val timer = remember { Animatable(0f) }
        var timerEpoch by remember { mutableIntStateOf(-1) }
        val holding = pressed || paused || typing || menu || confirmDelete || reportReasons != null || viewer.isDeleting
        LaunchedEffect(viewer.epoch) { paused = false }
        LaunchedEffect(muted) { player.setMuted(muted) }
        HotkeyHandler { hotkey ->
            // Пока пишется ответ, буквы и стрелки — для поля ввода.
            if (typing) return@HotkeyHandler false
            when (hotkey.action) {
                HotkeyAction.VIEWER_PREVIOUS -> true.also { act.onPrevious() }
                HotkeyAction.VIEWER_NEXT -> true.also { act.onNext() }
                HotkeyAction.VIEWER_PAUSE -> true.also { paused = !paused }
                HotkeyAction.VIEWER_MUTE -> true.also { muted = !muted }
                HotkeyAction.QUIT -> false
                else -> true
            }
        }
        // Фото, а также видео, которое не открылось (нет ffmpeg): идёт таймер по обложке.
        val asPhoto = media != null && (!media.isVideo || video.failed)
        LaunchedEffect(viewer.epoch, media) {
            if (media?.isVideo == true) player.open(media.url, userAgent, muted = false) else player.release()
            player.setMuted(muted)
        }
        LaunchedEffect(holding) {
            if (holding) player.pause() else if (media?.isVideo == true && !video.ended) player.play()
        }
        LaunchedEffect(video.ended) { if (video.ended && media?.isVideo == true) act.onNext() }
        LaunchedEffect(viewer.epoch, ready, holding, asPhoto) {
            if (timerEpoch != viewer.epoch) {
                timer.snapTo(0f)
                timerEpoch = viewer.epoch
            }
            if (!asPhoto || !ready || holding) return@LaunchedEffect
            val left = ((1f - timer.value) * PHOTO_DURATION_MS).toInt().coerceAtLeast(1)
            timer.animateTo(1f, tween(left, easing = LinearEasing))
            act.onNext()
        }

        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.88f))
                .pointerInput(Unit) { detectTapGestures(onTap = { act.onClose() }) },
        ) {
            // Карточка 9:16 по высоте окна: сверху шапка, снизу поле ответа.
            val cardHeight = (maxHeight - 190.dp).coerceAtLeast(240.dp)
            val cardWidth = minOf(cardHeight * 9f / 16f, maxWidth - 120.dp)
            val sideWidth = cardWidth * 0.36f
            val sideHeight = sideWidth * 16f / 9f
            val gap = 28.dp
            val available = maxWidth

            Row(
                Modifier.align(Alignment.Center),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(gap),
            ) {
                // Соседние авторы слева (дальний — левее).
                for (offset in 2 downTo 1) {
                    SideOwner(viewer, viewer.ownerIndex - offset, sideWidth, sideHeight, show = available > cardWidth + (sideWidth + gap) * 2 * offset) { act.onOwner(it) }
                }
                ArrowButton(left = true, enabled = viewer.ownerIndex > 0 || viewer.storyIndex > 0) { act.onPrevious() }
                Column(Modifier.width(cardWidth)) {
                    Header(viewer, video.isPlaying || (asPhoto && !holding), media?.isVideo == true, muted, busy, onPause = { paused = !paused }, onMute = { muted = !muted }, onMenu = { menu = true })
                    Box(Modifier.align(Alignment.End)) {
                        StoryMenu(
                            expanded = menu,
                            viewer = viewer,
                            actions = act,
                            onDismiss = { menu = false },
                            onDelete = { confirmDelete = true },
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Box(
                        Modifier
                            .width(cardWidth)
                            .height(cardHeight)
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.Black)
                            .pointerInput(Unit) {
                                detectTapGestures(
                                    onPress = {
                                        pressed = true
                                        tryAwaitRelease()
                                        pressed = false
                                    },
                                    onTap = { point -> if (point.x < size.width * 0.32f) act.onPrevious() else act.onNext() },
                                )
                            },
                    ) {
                        when {
                            viewer.isLoading || story == null || media == null -> CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
                            // Заново на каждый запуск: та же картинка снова сообщит о загрузке, и таймер пойдёт.
                            else -> key(viewer.epoch) {
                                AsyncImage(
                                    model = if (media.isVideo) media.thumbnailUrl else media.url,
                                    contentDescription = "История",
                                    contentScale = ContentScale.Fit,
                                    onSuccess = { ready = true },
                                    onError = { ready = true },
                                    modifier = Modifier.fillMaxSize(),
                                )
                                if (media.isVideo && !video.failed) {
                                    VideoFrame(video, Modifier.fillMaxSize())
                                    if (video.frame == null) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
                                }
                            }
                        }
                        Progress(viewer, asPhoto, timer.value, video.progress, Modifier.align(Alignment.TopCenter))
                    }
                    Spacer(Modifier.height(10.dp))
                    if (!viewer.isOwn && story != null) {
                        ReplyBar(
                            text = reply,
                            onText = { reply = it },
                            canReply = story.canReply,
                            canLike = story.canLike,
                            liked = story.isLiked,
                            busy = busy,
                            onFocus = { typing = it },
                            onSend = {
                                act.onReply(reply)
                                reply = ""
                            },
                            onLike = act.onLike,
                        )
                    }
                }
                ArrowButton(left = false, enabled = true) { act.onNext() }
                for (offset in 1..2) {
                    SideOwner(viewer, viewer.ownerIndex + offset, sideWidth, sideHeight, show = available > cardWidth + (sideWidth + gap) * 2 * offset) { act.onOwner(it) }
                }
            }
            IconButton(onClick = act.onClose, modifier = Modifier.align(Alignment.TopEnd).padding(12.dp)) {
                Icon(Icons.Filled.Close, "Закрыть", tint = Color.White, modifier = Modifier.size(28.dp))
            }
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text("Удалить историю?") },
                text = { Text("История исчезнет у всех, кто её ещё не посмотрел.") },
                confirmButton = {
                    TextButton(onClick = {
                        confirmDelete = false
                        act.onDelete()
                    }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
                },
                dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Отмена") } },
            )
        }
        reportReasons?.let { reasons ->
            AlertDialog(
                onDismissRequest = act.onCloseReport,
                title = { Text("Пожаловаться на историю") },
                text = {
                    if (reasons.isEmpty()) {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    } else {
                        Column {
                            reasons.forEach { reason ->
                                Text(
                                    reason.title,
                                    modifier = Modifier.fillMaxWidth().clickable { act.onReportReason(reason.id) }.padding(vertical = 10.dp),
                                )
                            }
                        }
                    }
                },
                confirmButton = {},
                dismissButton = { TextButton(onClick = act.onCloseReport) { Text("Отмена") } },
            )
        }
    }
}

/** Автор, время, пауза, звук (у видео) и «⋯». */
@Composable
private fun Header(
    viewer: StoryViewerState,
    playing: Boolean,
    isVideo: Boolean,
    muted: Boolean,
    busy: Boolean,
    onPause: () -> Unit,
    onMute: () -> Unit,
    onMenu: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().pointerInput(Unit) { detectTapGestures { } }) {
        Avatar(StoryText.avatar(viewer.ring), 40.dp)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f, fill = false)) {
            Text(StoryText.title(viewer.ring, viewer.isOwn), color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            viewer.story?.let {
                Text(StoryText.ago(it.timeMs, System.currentTimeMillis()), color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
            }
        }
        Spacer(Modifier.width(8.dp))
        IconButton(onClick = onPause) {
            Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) "Пауза (Пробел)" else "Смотреть (Пробел)", tint = Color.White)
        }
        if (isVideo) {
            IconButton(onClick = onMute) {
                Icon(if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp, if (muted) "Включить звук (M)" else "Выключить звук (M)", tint = Color.White)
            }
        }
        Spacer(Modifier.weight(1f))
        if (busy || viewer.isDeleting) {
            CircularProgressIndicator(Modifier.padding(12.dp).size(20.dp), color = Color.White, strokeWidth = 2.dp)
        }
        IconButton(onClick = onMenu) { Icon(Icons.Filled.MoreHoriz, "Ещё", tint = Color.White) }
    }
}

/** «⋯»: чужая история — профиль, скрыть автора, скачать, пожаловаться; своя — скачать и удалить. */
@Composable
private fun StoryMenu(expanded: Boolean, viewer: StoryViewerState, actions: StoryViewerActions, onDismiss: () -> Unit, onDelete: () -> Unit) {
    val story = viewer.story
    DropdownMenu(expanded = expanded && story != null, onDismissRequest = onDismiss) {
        if (story == null) return@DropdownMenu
        if (!viewer.isOwn && story.canOpenProfile) {
            DropdownMenuItem(text = { Text("Перейти в профиль") }, leadingIcon = { Icon(Icons.Outlined.AccountCircle, null) }, onClick = {
                onDismiss()
                actions.onProfile(viewer.ring)
            })
        }
        if (!viewer.isOwn && story.canHideAuthor) {
            DropdownMenuItem(text = { Text("Скрыть истории автора") }, leadingIcon = { Icon(Icons.Outlined.VisibilityOff, null) }, onClick = {
                onDismiss()
                actions.onHideAuthor()
            })
        }
        if (story.canDownload || viewer.isOwn) {
            DropdownMenuItem(text = { Text("Скачать") }, leadingIcon = { Icon(Icons.Outlined.Download, null) }, onClick = {
                onDismiss()
                actions.onDownload()
            })
        }
        if (!viewer.isOwn && story.canReport) {
            DropdownMenuItem(
                text = { Text("Пожаловаться", color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Outlined.ReportProblem, null, tint = MaterialTheme.colorScheme.error) },
                onClick = {
                    onDismiss()
                    actions.onReport()
                },
            )
        }
        if (viewer.isOwn) {
            DropdownMenuItem(
                text = { Text("Удалить", color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error) },
                onClick = {
                    onDismiss()
                    onDelete()
                },
            )
        }
    }
}

/** Полоски историй автора поверх карточки: просмотренные — белые, текущая заполняется. */
@Composable
private fun Progress(viewer: StoryViewerState, asPhoto: Boolean, timer: Float, video: Float, modifier: Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent)))
            .padding(horizontal = 10.dp, vertical = 10.dp)
            .height(3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        viewer.stories.indices.forEach { i ->
            val fill = when {
                i < viewer.storyIndex -> 1f
                i > viewer.storyIndex -> 0f
                asPhoto -> timer
                else -> video
            }
            Box(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(Color.White.copy(alpha = 0.35f))) {
                Box(Modifier.fillMaxHeight().fillMaxWidth(fill).background(Color.White))
            }
        }
    }
}

/** «Ответить» и сердечко под карточкой. Enter отправляет; пока поле в фокусе, история стоит. */
@Composable
private fun ReplyBar(
    text: String,
    onText: (String) -> Unit,
    canReply: Boolean,
    canLike: Boolean,
    liked: Boolean,
    busy: Boolean,
    onFocus: (Boolean) -> Unit,
    onSend: () -> Unit,
    onLike: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White.copy(alpha = 0.12f))
            .pointerInput(Unit) { detectTapGestures { } }
            .padding(start = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (canReply) {
                if (text.isEmpty()) Text("Ответить", color = Color.White.copy(alpha = 0.6f))
                androidx.compose.foundation.text.BasicTextField(
                    value = text,
                    onValueChange = onText,
                    singleLine = true,
                    textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
                    cursorBrush = SolidColor(Color.White),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                    keyboardActions = KeyboardActions(onSend = { if (text.isNotBlank()) onSend() }),
                    modifier = Modifier.fillMaxWidth().onFocusChanged { onFocus(it.isFocused) }.onEnterSend(text, onSend),
                )
            } else {
                Text("Автор выключил ответы", color = Color.White.copy(alpha = 0.5f), fontSize = 13.sp)
            }
        }
        if (canReply && text.isNotBlank()) {
            IconButton(onClick = onSend, enabled = !busy) { Icon(Icons.AutoMirrored.Filled.Send, "Отправить", tint = Color.White) }
        } else if (canLike) {
            IconButton(onClick = onLike) {
                Icon(
                    if (liked) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    if (liked) "Убрать лайк" else "Нравится",
                    tint = if (liked) Color(0xFFFF3B5C) else Color.White,
                )
            }
        }
    }
}

/** Enter в поле ответа отправляет (Shift+Enter в однострочном поле не нужен). */
private fun Modifier.onEnterSend(text: String, onSend: () -> Unit): Modifier = this.then(
    Modifier.onPreviewKeyEvent { event ->
        if (event.key == Key.Enter && event.type == KeyEventType.KeyDown) {
            if (text.isNotBlank()) onSend()
            true
        } else {
            false
        }
    },
)

/** Стрелка к соседней истории у карточки. */
@Composable
private fun ArrowButton(left: Boolean, enabled: Boolean, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(44.dp).pointerHoverIcon(PointerIcon.Hand),
    ) {
        Icon(
            if (left) Icons.AutoMirrored.Filled.KeyboardArrowLeft else Icons.AutoMirrored.Filled.KeyboardArrowRight,
            if (left) "Предыдущая история (←)" else "Следующая история (→)",
            tint = Color.White.copy(alpha = if (enabled) 0.9f else 0.3f),
            modifier = Modifier.size(36.dp),
        )
    }
}

/**
 * Соседний автор: размытая крупная аватарка на карточке, круглая аватарка и имя поверх; щелчок
 * открывает его истории. Нет автора или окно узкое — пустое место той же ширины.
 */
@Composable
private fun SideOwner(viewer: StoryViewerState, index: Int, width: Dp, height: Dp, show: Boolean, onOpen: (Int) -> Unit) {
    val ring = viewer.queue.getOrNull(index)
    if (!show) return
    if (ring == null) {
        Spacer(Modifier.width(width))
        return
    }
    val avatar = StoryText.avatar(ring)
    Box(
        Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.08f))
            .pointerHoverIcon(PointerIcon.Hand)
            .clickable { onOpen(index) },
        contentAlignment = Alignment.Center,
    ) {
        (avatar.kind as? app.maxly.presentation.chatlist.ChatAvatar.Kind.Photo)?.url?.let { url ->
            AsyncImage(url, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().blur(24.dp))
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier
                    .size(width * 0.5f)
                    .clip(CircleShape)
                    .background(if (ring.hasUnread) Brush.linearGradient(listOf(Color(0xFF6A5CFF), Color(0xFFB45CFF))) else SolidColor(Color.White.copy(alpha = 0.4f)))
                    .padding(3.dp),
                contentAlignment = Alignment.Center,
            ) {
                Avatar(avatar, width * 0.5f - 6.dp)
            }
            Spacer(Modifier.height(8.dp))
            Text(
                StoryText.title(ring, false),
                color = Color.White,
                fontWeight = FontWeight.SemiBold,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
    }
}
