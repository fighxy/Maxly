package app.maxly.ui.stories

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.runtime.rememberCoroutineScope
import app.maxly.domain.OutgoingStory
import androidx.compose.runtime.collectAsState
import app.maxly.ui.media.VideoFrame
import app.maxly.ui.media.rememberVideoPlayer
import app.maxly.platform.BackHandler
import app.maxly.ui.keys.HotkeyAction
import app.maxly.ui.keys.HotkeyHandler
import kotlinx.coroutines.launch
import app.maxly.domain.StoryAudience
import app.maxly.domain.StoryRing
import app.maxly.presentation.chatlist.ChatAvatar
import app.maxly.presentation.stories.StoriesUiState
import app.maxly.presentation.stories.StoryText
import app.maxly.presentation.stories.StoryViewerState
import app.maxly.ui.components.Avatar
import coil3.compose.AsyncImage
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
    /** «Скрыть истории автора» из меню чата: владелец и имя для сообщения. */
    val hide: (app.maxly.domain.StoryOwner, String) -> Unit = { _, _ -> },
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
 * удержание — пауза, свайп вниз или Escape — закрыть, вбок — к соседнему владельцу. Видео
 * играет встроенный проигрыватель (ffmpeg); без ffmpeg история показывает обложку 5 секунд.
 */
/** Новая история: предпросмотр выбранного файла, кому показать и «Опубликовать». История живёт сутки. */
@Composable
fun StoryComposer(story: OutgoingStory, userAgent: String, onPublish: (StoryAudience) -> Unit, onCancel: () -> Unit) {
    var audience by remember { mutableStateOf(StoryAudience.EVERYONE) }
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BackHandler(onBack = onCancel)
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (story.isVideo) {
                // Предпросмотр по кругу без звука; без ffmpeg — значок и имя файла.
                val preview = rememberVideoPlayer()
                val state by preview.state.collectAsState()
                LaunchedEffect(story.path) { preview.open(story.path, userAgent, muted = true, loop = true) }
                if (state.failed) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Outlined.Movie, null, tint = Color.White, modifier = Modifier.size(72.dp))
                        Spacer(Modifier.height(8.dp))
                        Text(File(story.path).name, color = Color.White.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                } else {
                    VideoFrame(state, Modifier.fillMaxSize())
                }
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
