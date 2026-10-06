package app.orbitle.ui.stories

import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import app.orbitle.presentation.stories.StoryStripMotion

/**
 * Полоса историй сжимается поднятием списка от верхнего края и тянется обратно вниз.
 * Поиск и перестановка закреплённых прячут её, не меняя запомненное состояние.
 */
@Stable
class StoryStripHandle(collapsed: Boolean) {
    var onCollapsedChange: (Boolean) -> Unit = {}
    var reveal by mutableFloatStateOf(if (collapsed) 0f else 1f)
        private set
    var expanded by mutableStateOf(!collapsed)
        private set
    var forceHidden by mutableStateOf(false)
    var listAtTop by mutableStateOf(true)
    var reduceMotion by mutableStateOf(false)
    var dragging by mutableStateOf(false)
        private set

    /** Обновление потягиванием: полоса уже открыта и жест её сейчас не двигает. */
    val canRefresh: Boolean
        get() = StoryStripMotion.refreshesOnPull(expanded) && reveal >= 1f && !forceHidden && !dragging

    val visual: Float
        get() = if (forceHidden) 0f else reveal

    internal var thresholdPx: Float = 48f * 3
    private var heightPx = 1f
    private var originExpanded = !collapsed
    private var gesture = false
    private var appliedCollapsed = collapsed

    fun syncCollapsed(collapsed: Boolean) {
        if (dragging || collapsed == appliedCollapsed) return
        appliedCollapsed = collapsed
        expanded = !collapsed
        originExpanded = expanded
        reveal = if (collapsed) 0f else 1f
    }

    fun setHeight(px: Int) {
        if (px > 0) heightPx = px.toFloat()
    }

    val connection: NestedScrollConnection = object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (shouldIgnore(source)) return Offset.Zero
            // Палец вверх: сначала уезжает полоса, список трогается после неё.
            if (available.y < 0f && reveal > 0f && listAtTop) return consume(available.y)
            return Offset.Zero
        }

        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (shouldIgnore(source)) return Offset.Zero
            // Список уже у края и не взял движение вниз — это открытие полосы, не обновление.
            if (available.y > 0f && reveal < 1f && listAtTop) return consume(available.y)
            return Offset.Zero
        }

        override suspend fun onPreFling(available: Velocity): Velocity {
            if (!gesture) return Velocity.Zero
            val openedByThisGesture = !originExpanded
            finishGesture()
            // Жест открыл полосу: этот же рывок не запускает обновление списка.
            return if (openedByThisGesture) available else Velocity.Zero
        }
    }

    /** Поиск и папки: то же движение, даже если список прокручен. */
    fun headerDrag(): Modifier = Modifier.pointerInput(this) {
        detectVerticalDragGestures(
            onDragStart = { beginGesture() },
            onDragCancel = { finishGesture() },
            onDragEnd = { finishGesture() },
            onVerticalDrag = { change, amount ->
                change.consume()
                consume(amount, fromHeader = true)
            },
        )
    }

    private fun shouldIgnore(source: NestedScrollSource): Boolean =
        forceHidden || source != NestedScrollSource.UserInput

    private fun beginGesture() {
        if (gesture) return
        gesture = true
        dragging = true
        originExpanded = expanded
    }

    private fun consume(dy: Float, fromHeader: Boolean = false): Offset {
        if (forceHidden) return Offset.Zero
        if (!fromHeader && !listAtTop) return Offset.Zero
        beginGesture()
        val height = heightPx.coerceAtLeast(1f)
        val before = reveal
        val drag = (before - if (originExpanded) 1f else 0f) * height + dy
        val moved = StoryStripMotion.reveal(originExpanded, drag, height, atTop = true)
        reveal = if (reduceMotion) {
            if (StoryStripMotion.settledExpanded(originExpanded, drag, atTop = true, thresholdPx)) 1f else 0f
        } else {
            moved
        }
        return Offset(0f, (reveal - before) * height)
    }

    private fun finishGesture() {
        if (!gesture) return
        val drag = (reveal - if (originExpanded) 1f else 0f) * heightPx.coerceAtLeast(1f)
        val open = StoryStripMotion.settledExpanded(originExpanded, drag, atTop = true, thresholdPx)
        expanded = open
        reveal = if (open) 1f else 0f
        dragging = false
        gesture = false
        appliedCollapsed = !open
        onCollapsedChange(!open)
    }
}

@Composable
fun rememberStoryStripHandle(collapsed: Boolean, onCollapsedChange: (Boolean) -> Unit): StoryStripHandle {
    val handle = remember { StoryStripHandle(collapsed) }
    handle.onCollapsedChange = onCollapsedChange
    handle.syncCollapsed(collapsed)
    handle.thresholdPx = with(LocalDensity.current) { StoryStripMotion.THRESHOLD_DP.dp.toPx() }
    return handle
}

/** Полоса заданной доли высоты. Низ остаётся у поиска, верх уезжает за обрез. */
@Composable
fun StoryStripSlot(handle: StoryStripHandle, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val visual = handle.visual
    SubcomposeLayout(modifier.clipToBounds().then(handle.headerDrag())) { constraints ->
        val placeable = subcompose("strip") { content() }.firstOrNull()?.measure(
            constraints.copy(minWidth = constraints.maxWidth, minHeight = 0, maxHeight = Constraints.Infinity),
        )
        val full = placeable?.height ?: 0
        handle.setHeight(full)
        val height = (full * visual).toInt().coerceIn(0, full)
        layout(constraints.maxWidth, height) {
            placeable?.place(0, height - full)
        }
    }
}
