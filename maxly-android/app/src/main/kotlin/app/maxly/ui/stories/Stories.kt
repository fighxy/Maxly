package app.maxly.ui.stories

import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.imePadding
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.ui.focus.onFocusChanged
import app.maxly.data.ComplaintChoice
import app.maxly.presentation.stories.StoryViewerActions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.zIndex
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
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
import app.maxly.domain.OutgoingStory
import app.maxly.domain.StoryAudience
import app.maxly.domain.StoryRing
import app.maxly.media.MediaSources
import app.maxly.presentation.chatlist.ChatAvatar
import app.maxly.presentation.stories.StoriesUiState
import app.maxly.presentation.stories.StoryText
import app.maxly.presentation.stories.StoryViewerState
import app.maxly.ui.components.Avatar
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay
import java.io.File
import kotlin.math.abs

/** Кольца историй для строк списка, шапки чата и профиля: кто с историями и как их открыть. */
class StoryRings(
    val state: StoriesUiState,
    val open: (String) -> Unit,
    /** Спросить кольцо человека вне ленты (открытый профиль). */
    val load: (String?) -> Unit = {},
    /** Спросить кольцо человека, группы или канала. */
    val loadOwner: (String?, app.maxly.domain.StoryOwner.Type) -> Unit = { id, _ -> load(id) },
) {
    fun ringOf(ownerId: String?): StoryRing? = state.ringOf(ownerId)
    fun ringFor(ownerId: String?, type: app.maxly.domain.StoryOwner.Type): StoryRing? = state.ringFor(ownerId, type)
}

val LocalStoryRings = compositionLocalOf { StoryRings(StoriesUiState(), open = {}) }

/** Непросмотренные сегменты кольца. */
private val UnseenColors = listOf(Color(0xFF5AC8FA), Color(0xFF34C759))

/** Сколько длится фото-история. */
private const val PHOTO_MS = 5_000

/**
 * Аватар с кольцом историй: сегмент на историю, просмотренные — тусклые. Без кольца — обычный
 * аватар того же размера. [progress] — кольцо публикации вместо сегментов.
 */
@Composable
fun StoryRingAvatar(
    avatar: ChatAvatar,
    ring: StoryRing?,
    size: Dp,
    modifier: Modifier = Modifier,
    online: Boolean = false,
    progress: Float? = null,
    onRingClick: (() -> Unit)? = null,
) {
    if (ring == null && progress == null) {
        Avatar(avatar, size, modifier, online)
        return
    }
    val stroke = (size.value * 0.045f).coerceIn(2f, 3.5f).dp
    val seen = MaterialTheme.colorScheme.outlineVariant
    val click = if (onRingClick != null && ring != null) Modifier.clip(CircleShape).clickable(onClick = onRingClick) else Modifier
    Box(modifier.size(size).then(click), contentAlignment = Alignment.Center) {
        Canvas(Modifier.matchParentSize()) { drawStoryRing(ring, stroke.toPx(), seen, progress) }
        Avatar(avatar, size - stroke * 4, online = online)
    }
}

private fun DrawScope.drawStoryRing(ring: StoryRing?, stroke: Float, seen: Color, progress: Float?) {
    val brush = Brush.linearGradient(UnseenColors, start = Offset(0f, size.height), end = Offset(size.width, 0f))
    val topLeft = Offset(stroke / 2, stroke / 2)
    val arc = Size(size.width - stroke, size.height - stroke)
    if (progress != null) {
        drawArc(seen, 0f, 360f, false, topLeft, arc, style = Stroke(stroke))
        drawArc(brush, -90f, 360f * progress.coerceIn(0.02f, 1f), false, topLeft, arc, style = Stroke(stroke, cap = StrokeCap.Round))
        return
    }
    val (count, read) = StoryText.segments(ring ?: return)
    val step = 360f / count
    // Круглые концы съедают часть зазора: добавляем их угловую ширину.
    val capDegrees = Math.toDegrees((stroke / (arc.width / 2)).toDouble()).toFloat()
    val gap = if (count > 1) (step * 0.12f).coerceIn(3f, 10f) + capDegrees else 0f
    for (i in 0 until count) {
        val start = -90f + i * step + gap / 2
        val sweep = (step - gap).coerceAtLeast(0.5f)
        val style = Stroke(stroke, cap = if (count > 1) StrokeCap.Round else StrokeCap.Butt)
        if (i < read) drawArc(seen, start, sweep, false, topLeft, arc, style = style)
        else drawArc(brush, start, sweep, false, topLeft, arc, style = style)
    }
}

/** Стопка аватаров историй у заголовка списка, пока полоса спрятана над поиском. */
@Composable
fun StoryStack(items: List<Pair<ChatAvatar, StoryRing>>, modifier: Modifier = Modifier) {
    val shown = items.take(3)
    if (shown.isEmpty()) return
    Box(modifier.width((28 + 16 * (shown.size - 1)).dp)) {
        shown.forEachIndexed { index, (avatar, ring) ->
            StoryRingAvatar(
                avatar,
                ring,
                28.dp,
                Modifier.offset(x = (16 * index).dp).zIndex((shown.size - index).toFloat()),
            )
        }
    }
}

/** Полоса историй над списком чатов: «Ваша история» и кольца остальных. */
@Composable
fun StoriesStrip(
    state: StoriesUiState,
    self: ChatAvatar,
    onOpen: (String) -> Unit,
    onAdd: () -> Unit,
    modifier: Modifier = Modifier,
    /** «Открыть мои истории» в меню своего кружка (долгое нажатие); `null` — архива нет. */
    onArchive: (() -> Unit)? = null,
) {
    var ownMenu by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    LazyRow(
        modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        item(key = "self") {
            val own = state.own
            Tile(
                title = StoryText.YOUR_STORY,
                dim = false,
                onClick = { if (own != null) onOpen(own.owner.id) else onAdd() },
                onLongClick = onArchive?.let { { ownMenu = true } },
            ) {
                Box {
                    androidx.compose.material3.DropdownMenu(expanded = ownMenu, onDismissRequest = { ownMenu = false }) {
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text("Новая история") },
                            onClick = {
                                ownMenu = false
                                onAdd()
                            },
                        )
                        if (onArchive != null) {
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text("Открыть мои истории") },
                                onClick = {
                                    ownMenu = false
                                    onArchive()
                                },
                            )
                        }
                    }
                    StoryRingAvatar(self, own, 60.dp, progress = state.publishProgress)
                    Box(
                        Modifier
                            .align(Alignment.BottomEnd)
                            .size(22.dp)
                            .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                            .clickable(onClick = onAdd),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.Add, "Новая история", tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(14.dp))
                    }
                }
            }
        }
        items(state.rings, key = { it.owner.id }) { ring ->
            Tile(title = StoryText.title(ring, own = false), dim = !ring.hasUnread, onClick = { onOpen(ring.owner.id) }) {
                StoryRingAvatar(StoryText.avatar(ring), ring, 60.dp)
            }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun Tile(title: String, dim: Boolean, onClick: () -> Unit, onLongClick: (() -> Unit)? = null, avatar: @Composable () -> Unit) {
    Column(
        Modifier.width(72.dp).clip(RoundedCornerShape(12.dp))
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        avatar()
        Spacer(Modifier.height(4.dp))
        Text(
            title,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            color = if (dim) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(horizontal = 2.dp),
        )
    }
}

/**
 * Просмотр историй на весь экран. Касание слева (треть ширины) — назад, справа — вперёд,
 * удержание — пауза, свайп вниз — закрыть, вбок — к соседнему владельцу.
 */
@Composable
fun StoryViewer(
    viewer: StoryViewerState,
    userAgent: String,
    actions: StoryViewerActions,
    busy: Boolean = false,
    reportReasons: List<ComplaintChoice>? = null,
) {
    Dialog(onDismissRequest = actions.onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = actions.onClose)
        val act by rememberUpdatedState(actions)
        var pressed by remember { mutableStateOf(false) }
        var dragging by remember { mutableStateOf(false) }
        var paused by remember { mutableStateOf(false) }
        var muted by remember { mutableStateOf(false) }
        var typing by remember { mutableStateOf(false) }
        var menu by remember { mutableStateOf(false) }
        var confirmDelete by remember { mutableStateOf(false) }
        var reply by remember(viewer.epoch) { mutableStateOf("") }
        var dragX by remember { mutableFloatStateOf(0f) }
        var dragY by remember { mutableFloatStateOf(0f) }
        val story = viewer.story
        val media = story?.media
        var ready by remember(viewer.epoch) { mutableStateOf(false) }
        var videoFailed by remember(viewer.epoch) { mutableStateOf(false) }
        var videoProgress by remember(viewer.epoch) { mutableFloatStateOf(0f) }
        val timer = remember { Animatable(0f) }
        var timerEpoch by remember { mutableIntStateOf(-1) }
        val holding = pressed || dragging || paused || typing || menu || confirmDelete || reportReasons != null || viewer.isDeleting
        val asPhoto = media != null && (!media.isVideo || videoFailed)
        LaunchedEffect(viewer.epoch) { paused = false }
        LaunchedEffect(viewer.epoch, ready, holding, asPhoto) {
            if (timerEpoch != viewer.epoch) {
                timer.snapTo(0f)
                timerEpoch = viewer.epoch
            }
            if (!asPhoto || !ready || holding) return@LaunchedEffect
            val left = ((1f - timer.value) * PHOTO_MS).toInt().coerceAtLeast(1)
            timer.animateTo(1f, tween(left, easing = LinearEasing))
            act.onNext()
        }
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black)
                .imePadding(),
        ) {
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onPress = {
                                pressed = true
                                tryAwaitRelease()
                                pressed = false
                            },
                            onTap = { point -> if (point.x < size.width * 0.32f) act.onPrevious() else act.onNext() },
                        )
                    }
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDragStart = { dragging = true },
                            onDragEnd = {
                                val down = dragY > 140.dp.toPx()
                                val side = abs(dragX) > 90.dp.toPx() && abs(dragX) > dragY
                                when {
                                    down -> act.onClose()
                                    side && dragX < 0 -> act.onNextOwner()
                                    side -> act.onPreviousOwner()
                                }
                                dragX = 0f
                                dragY = 0f
                                dragging = false
                            },
                            onDragCancel = {
                                dragX = 0f
                                dragY = 0f
                                dragging = false
                            },
                            onDrag = { change, amount ->
                                change.consume()
                                dragX += amount.x
                                dragY = (dragY + amount.y).coerceAtLeast(0f)
                            },
                        )
                    }
                    .graphicsLayer {
                        translationY = dragY
                        val shrink = (dragY / 3000f).coerceAtMost(0.15f)
                        scaleX = 1f - shrink
                        scaleY = 1f - shrink
                    },
            ) {
                when {
                    viewer.isLoading || story == null || media == null -> CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
                    // Заново на каждый запуск: та же картинка снова сообщит о загрузке, и таймер пойдёт.
                    asPhoto -> key(viewer.epoch) {
                        AsyncImage(
                            model = if (media.isVideo) media.thumbnailUrl else media.url,
                            contentDescription = "История",
                            contentScale = ContentScale.Fit,
                            onSuccess = { ready = true },
                            onError = { ready = true },
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                    else -> {
                        media.thumbnailUrl?.let { AsyncImage(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
                        VideoStory(
                            url = media.url,
                            userAgent = userAgent,
                            epoch = viewer.epoch,
                            playing = !holding,
                            muted = muted,
                            onProgress = { videoProgress = it },
                            onEnded = { act.onNext() },
                            onFailed = { videoFailed = true },
                        )
                    }
                }
            }
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent)))
                    .statusBarsPadding()
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            ) {
                Row(Modifier.fillMaxWidth().height(3.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    viewer.stories.indices.forEach { i ->
                        val fill = when {
                            i < viewer.storyIndex -> 1f
                            i > viewer.storyIndex -> 0f
                            asPhoto -> timer.value
                            else -> videoProgress
                        }
                        Box(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(Color.White.copy(alpha = 0.35f))) {
                            Box(Modifier.fillMaxHeight().fillMaxWidth(fill).background(Color.White))
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(StoryText.avatar(viewer.ring), 36.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(StoryText.title(viewer.ring, viewer.isOwn), color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        story?.let {
                            Text(StoryText.ago(it.timeMs, System.currentTimeMillis()), color = Color.White.copy(alpha = 0.75f), fontSize = 12.sp)
                        }
                    }
                    if (busy || viewer.isDeleting) {
                        CircularProgressIndicator(Modifier.padding(12.dp).size(20.dp), color = Color.White, strokeWidth = 2.dp)
                    }
                    IconButton(onClick = { paused = !paused }) {
                        Icon(if (paused) Icons.Filled.PlayArrow else Icons.Filled.Pause, if (paused) "Смотреть" else "Пауза", tint = Color.White)
                    }
                    if (media?.isVideo == true && !videoFailed) {
                        IconButton(onClick = { muted = !muted }) {
                            Icon(if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp, if (muted) "Включить звук" else "Выключить звук", tint = Color.White)
                        }
                    }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "Ещё", tint = Color.White) }
                        StoryMenu(menu, viewer, act, onDismiss = { menu = false }, onDelete = { confirmDelete = true })
                    }
                    IconButton(onClick = act.onClose) { Icon(Icons.Filled.Close, "Закрыть", tint = Color.White) }
                }
            }
            if (!viewer.isOwn && story != null) {
                StoryReplyBar(
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
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
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
                                Text(reason.title, modifier = Modifier.fillMaxWidth().clickable { act.onReportReason(reason.id) }.padding(vertical = 12.dp))
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

/** «⋮»: чужая история — профиль, скрыть автора, скачать, пожаловаться; своя — скачать и удалить. */
@Composable
private fun StoryMenu(expanded: Boolean, viewer: StoryViewerState, actions: StoryViewerActions, onDismiss: () -> Unit, onDelete: () -> Unit) {
    val story = viewer.story ?: return
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
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

/** «Ответить» и сердечко внизу. Пока поле в фокусе, история стоит. */
@Composable
private fun StoryReplyBar(
    text: String,
    onText: (String) -> Unit,
    canReply: Boolean,
    canLike: Boolean,
    liked: Boolean,
    busy: Boolean,
    onFocus: (Boolean) -> Unit,
    onSend: () -> Unit,
    onLike: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .pointerInput(Unit) { detectTapGestures { } },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .weight(1f)
                .height(48.dp)
                .clip(RoundedCornerShape(24.dp))
                .border(1.dp, Color.White.copy(alpha = 0.4f), RoundedCornerShape(24.dp))
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (canReply) {
                if (text.isEmpty()) Text("Ответить", color = Color.White.copy(alpha = 0.6f))
                androidx.compose.foundation.text.BasicTextField(
                    value = text,
                    onValueChange = onText,
                    singleLine = true,
                    textStyle = androidx.compose.ui.text.TextStyle(color = Color.White, fontSize = 15.sp),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(Color.White),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Send),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSend = { if (text.isNotBlank()) onSend() }),
                    modifier = Modifier.fillMaxWidth().onFocusChanged { onFocus(it.isFocused) },
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

/** Видео-история: Media3 без кнопок, ход — в полосу прогресса, конец — к следующей истории. */
@OptIn(UnstableApi::class)
@Composable
private fun VideoStory(
    url: String,
    userAgent: String,
    epoch: Int,
    playing: Boolean,
    muted: Boolean,
    onProgress: (Float) -> Unit,
    onEnded: () -> Unit,
    onFailed: () -> Unit,
) {
    val context = LocalContext.current
    val ended by rememberUpdatedState(onEnded)
    val failed by rememberUpdatedState(onFailed)
    val player = remember(url, epoch) {
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(MediaSources.factory(context, userAgent))
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri(url))
                prepare()
            }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) ended()
            }

            override fun onPlayerError(error: PlaybackException) = failed()
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    LaunchedEffect(player, playing) { player.playWhenReady = playing }
    LaunchedEffect(player, muted) { player.volume = if (muted) 0f else 1f }
    LaunchedEffect(player) {
        while (true) {
            val duration = player.duration
            if (duration > 0) onProgress((player.currentPosition.toFloat() / duration).coerceIn(0f, 1f))
            delay(50)
        }
    }
    // TextureView: полоса прогресса и кнопки — Compose поверх кадра, SurfaceView их перекрыл бы.
    ContentFrame(
        player = player,
        modifier = Modifier.fillMaxSize(),
        surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
        contentScale = ContentScale.Fit,
        shutter = {},
    )
}

/** Новая история: предпросмотр выбранного файла, кому показать и «Опубликовать». История живёт сутки. */
@OptIn(UnstableApi::class)
@Composable
fun StoryComposer(story: OutgoingStory, userAgent: String, onPublish: (StoryAudience) -> Unit, onCancel: () -> Unit) {
    var audience by remember { mutableStateOf(StoryAudience.EVERYONE) }
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = onCancel)
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (story.isVideo) {
                val context = LocalContext.current
                val player = remember(story.path) {
                    ExoPlayer.Builder(context)
                        .setMediaSourceFactory(MediaSources.factory(context, userAgent))
                        .build()
                        .apply {
                            setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(File(story.path))))
                            repeatMode = Player.REPEAT_MODE_ONE
                            volume = 0f
                            playWhenReady = true
                            prepare()
                        }
                }
                DisposableEffect(player) { onDispose { player.release() } }
                ContentFrame(
                    player = player,
                    modifier = Modifier.fillMaxSize(),
                    surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
                    contentScale = ContentScale.Fit,
                )
            } else {
                AsyncImage(File(story.path), "Новая история", Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            }
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onCancel) { Icon(Icons.Filled.Close, "Отмена", tint = Color.White) }
                Text("Новая история", color = Color.White, style = MaterialTheme.typography.titleMedium)
            }
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))))
                    .navigationBarsPadding()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Кто увидит", color = Color.White.copy(alpha = 0.8f), fontSize = 13.sp)
                Spacer(Modifier.height(8.dp))
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    val options = listOf(StoryAudience.EVERYONE to "Все", StoryAudience.CONTACTS to "Контакты")
                    options.forEachIndexed { index, (value, label) ->
                        SegmentedButton(
                            selected = audience == value,
                            onClick = { audience = value },
                            shape = SegmentedButtonDefaults.itemShape(index, options.size),
                            colors = SegmentedButtonDefaults.colors(
                                inactiveContainerColor = Color.Transparent,
                                inactiveContentColor = Color.White,
                                inactiveBorderColor = Color.White.copy(alpha = 0.5f),
                                activeBorderColor = Color.White.copy(alpha = 0.5f),
                            ),
                        ) { Text(label) }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Button(onClick = { onPublish(audience) }, modifier = Modifier.fillMaxWidth()) { Text("Опубликовать на сутки") }
            }
        }
    }
}
