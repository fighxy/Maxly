package app.orbitle.ui.chatlist

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.orbitle.presentation.chatlist.ChatFolderTab
import app.orbitle.presentation.chatlist.ChatListHeaderGeometry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Положение шапки списка чатов (истории, поиск, папки) — как в Telegram и на iOS. Список
 * встаёт на поиск, истории спрятаны над ним. Подъём списка сначала уводит поиск, папки
 * остаются; у верха списка палец тянет поиск и истории обратно, инерция встаёт на поиске.
 *
 * [snapOnIdle] — на ПК колесо не даёт «отпускания», поэтому шапка доезжает до края после паузы.
 */
@Stable
class ChatListHeaderState(private val snapOnIdle: Boolean) {
    var geometry by mutableStateOf(ChatListHeaderGeometry(0f, 0f))
        private set
    var top by mutableFloatStateOf(0f)
        private set

    /** Поиск или перестановка закреплённых: шапка не двигается. */
    var enabled by mutableStateOf(true)

    val storiesHidden: Boolean get() = geometry.storiesHidden(top)
    val foldersPinned: Boolean get() = geometry.foldersPinned(top)

    internal var scope: CoroutineScope? = null
    internal var slackPx = 0f
    private var placed = false
    private var settle: Job? = null
    private var idle: Job? = null

    internal fun measured(stories: Int, search: Int) {
        val next = ChatListHeaderGeometry(stories.toFloat(), search.toFloat(), slackPx)
        if (next == geometry) return
        val old = geometry
        geometry = next
        top = if (!placed) next.storiesHiddenTop else next.remeasured(top, old)
        placed = placed || stories > 0 || search > 0
    }

    val connection: NestedScrollConnection = object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            // Палец вверх: сначала уезжает шапка, потом список.
            if (!enabled || available.y >= 0f) return Offset.Zero
            return Offset(0f, move(available.y, fling = source != NestedScrollSource.UserInput))
        }

        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            // Список дошёл до верха и не взял движение вниз — выезжает шапка.
            if (!enabled || available.y <= 0f) return Offset.Zero
            return Offset(0f, move(available.y, fling = source != NestedScrollSource.UserInput))
        }

        override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
            snap()
            return Velocity.Zero
        }
    }

    /** Тянуть можно и саму шапку: поиск и папки. */
    internal fun drag(dy: Float) {
        if (enabled) move(dy, fling = false)
    }

    /** Нажатие на заголовок: открыть или спрятать истории. */
    fun toggleStories() {
        animateTo(if (storiesHidden) 0f else geometry.storiesHiddenTop)
    }

    /** Вернуть список на поиск: истории спрятаны. */
    fun reset() {
        settle?.cancel()
        top = geometry.storiesHiddenTop
    }

    internal fun snap() {
        geometry.snapTarget(top)?.let(::animateTo)
    }

    private fun move(dy: Float, fling: Boolean): Float {
        if (!fling) settle?.cancel()
        val next = geometry.scrolled(top, dy, fling)
        val used = top - next
        top = next
        if (snapOnIdle && used != 0f) {
            idle?.cancel()
            idle = scope?.launch {
                delay(180)
                snap()
            }
        }
        return used
    }

    private fun animateTo(target: Float) {
        settle?.cancel()
        settle = scope?.launch {
            animate(top, target, animationSpec = tween(220)) { value, _ -> top = value }
        }
    }
}

@Composable
fun rememberChatListHeaderState(snapOnIdle: Boolean = false): ChatListHeaderState {
    val state = remember { ChatListHeaderState(snapOnIdle) }
    state.scope = rememberCoroutineScope()
    state.slackPx = with(LocalDensity.current) { 8.dp.toPx() }
    return state
}

/**
 * Истории, поиск и папки одним столбцом, сдвинутым на [ChatListHeaderState.top]. Высота —
 * видимая часть; папки не уезжают никогда. Истории и поиск тают, уходя под панель.
 */
@Composable
fun ChatListHeader(
    state: ChatListHeaderState,
    stories: (@Composable () -> Unit)?,
    search: @Composable () -> Unit,
    folders: (@Composable () -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val drag = rememberDraggableState { state.drag(it) }
    SubcomposeLayout(
        modifier.clipToBounds().draggable(drag, Orientation.Vertical, onDragStopped = { state.snap() }),
    ) { constraints ->
        val loose = constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity)
        val storyRow = stories?.let { content -> subcompose("stories", content).map { it.measure(loose) } }.orEmpty()
        val searchRow = subcompose("search", search).map { it.measure(loose) }
        val folderRow = folders?.let { content -> subcompose("folders", content).map { it.measure(loose) } }.orEmpty()
        val storiesHeight = storyRow.maxOfOrNull { it.height } ?: 0
        val searchHeight = searchRow.maxOfOrNull { it.height } ?: 0
        val foldersHeight = folderRow.maxOfOrNull { it.height } ?: 0
        state.measured(storiesHeight, searchHeight)
        val top = state.top.roundToInt().coerceIn(0, storiesHeight + searchHeight)
        val height = storiesHeight + searchHeight + foldersHeight - top
        layout(constraints.maxWidth, height) {
            val storiesAlpha = if (storiesHeight > 0) (1f - top.toFloat() / storiesHeight).coerceIn(0f, 1f) else 0f
            val searchAlpha = if (searchHeight > 0) (1f - (top - storiesHeight).toFloat() / searchHeight).coerceIn(0f, 1f) else 0f
            storyRow.forEach { it.placeWithLayer(0, -top) { alpha = storiesAlpha } }
            searchRow.forEach { it.placeWithLayer(0, storiesHeight - top) { alpha = searchAlpha } }
            folderRow.forEach { it.place(0, storiesHeight + searchHeight - top) }
        }
    }
}

/** Поиск в шапке: капсула с подсказкой по центру, нажатие открывает поиск. */
@Composable
fun SearchCapsule(placeholder: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .height(36.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Search, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(6.dp))
            Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
        }
    }
}

/**
 * Папки капсулой, как в Telegram: выбранную отмечает «таблетка», которая едет за листанием
 * страниц ([pageOffset] — доля пути к соседней странице).
 */
@Composable
fun FolderCapsule(
    folders: List<ChatFolderTab>,
    selected: Int,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    pageOffset: Float = 0f,
) {
    val scroll = rememberScrollState()
    val bounds = remember { mutableStateMapOf<Int, Pair<Float, Float>>() }
    val pill = remember { Animatable(0f) }
    val pillWidth = remember { Animatable(0f) }
    val density = LocalDensity.current
    val target = pillTarget(bounds, selected, pageOffset)
    LaunchedEffect(target, pageOffset == 0f) {
        val (x, width) = target ?: return@LaunchedEffect
        if (pageOffset != 0f || pillWidth.value == 0f) {
            pill.snapTo(x)
            pillWidth.snapTo(width)
        } else {
            launch { pill.animateTo(x, tween(220)) }
            pillWidth.animateTo(width, tween(220))
        }
    }
    LaunchedEffect(selected, bounds[selected]) { bounds[selected]?.let { (x, width) -> reveal(scroll, x, width, density.density) } }
    Box(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .height(40.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        Box(Modifier.horizontalScroll(scroll).padding(4.dp).height(32.dp)) {
            if (pillWidth.value > 0f) {
                Box(
                    Modifier
                        .offset { IntOffset(pill.value.roundToInt(), 0) }
                        .width(with(density) { pillWidth.value.toDp() })
                        .height(32.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(0.dp), verticalAlignment = Alignment.CenterVertically) {
                folders.forEachIndexed { index, folder ->
                    Row(
                        Modifier
                            .height(32.dp)
                            .widthIn(min = 48.dp)
                            .clip(CircleShape)
                            .clickable { onSelect(folder.id) }
                            .onPlaced { bounds[index] = it.positionInParent().x to it.size.width.toFloat() }
                            .padding(horizontal = 13.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            folder.title,
                            fontSize = 15.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = if (index == selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        folder.badge?.let { badge ->
                            Spacer(Modifier.width(6.dp))
                            Badge(containerColor = MaterialTheme.colorScheme.primary) { Text(badge) }
                        }
                    }
                }
            }
        }
    }
}

/** Где стоять таблетке: на выбранной папке или между ней и соседней при листании. */
private fun pillTarget(bounds: Map<Int, Pair<Float, Float>>, selected: Int, pageOffset: Float): Pair<Float, Float>? {
    val from = bounds[selected] ?: return null
    if (pageOffset == 0f) return from
    val to = bounds[selected + if (pageOffset > 0f) 1 else -1] ?: return from
    val t = abs(pageOffset).coerceIn(0f, 1f)
    return (from.first + (to.first - from.first) * t) to (from.second + (to.second - from.second) * t)
}

/** Выбранная папка целиком в капсуле, с соседом по краю. */
private suspend fun reveal(scroll: ScrollState, x: Float, width: Float, density: Float) {
    val margin = 24f * density
    val viewport = scroll.viewportSize.toFloat()
    if (viewport <= 0f) return
    val left = scroll.value.toFloat()
    when {
        x - margin < left -> scroll.animateScrollTo((x - margin).roundToInt().coerceAtLeast(0))
        x + width + margin > left + viewport -> scroll.animateScrollTo((x + width + margin - viewport).roundToInt())
    }
}
