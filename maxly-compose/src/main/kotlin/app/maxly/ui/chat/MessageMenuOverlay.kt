package app.maxly.ui.chat

// Меню сообщения по долгому нажатию, как в WhatsApp и на iOS (`MessageMenuOverlay`): лента
// притемнена, копия строки сообщения поднята на своём месте (или сдвинута, чтобы всё влезло),
// над ней капсула реакций с «+», под ней пункты и «Ещё…». Общее для Android и десктопа.

import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maxly.ui.components.clickCursor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Пункт меню сообщения. */
data class MenuAction(
    val label: String,
    val icon: ImageVector,
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/**
 * Меню сообщения поверх экрана чата. [anchor] — строка сообщения в координатах корня, [preview]
 * рисует её копию той же ширины. Пункт выполняется после закрытия меню: листы и подтверждения
 * открываются уже без него.
 */
@Composable
fun MessageMenuOverlay(
    anchor: Rect,
    outgoing: Boolean,
    /** Быстрые реакции; `null` — реакции ставить нельзя. */
    reactions: List<String>?,
    /** Своя реакция: в капсуле отмечена, нажатие снимает её. */
    mine: String?,
    onReact: (String) -> Unit,
    /** «+» в капсуле: полный выбор реакций; `null` — кнопки нет. */
    onMoreReactions: (() -> Unit)?,
    /** Главные пункты: «Ответить», «Изменить», «Переслать», «Копировать», «Сведения», «Удалить». */
    primary: List<MenuAction>,
    /** Остальное — под «Ещё…». */
    more: List<MenuAction>,
    onDismiss: () -> Unit,
    preview: @Composable () -> Unit,
) {
    var origin by remember { mutableStateOf<Offset?>(null) }
    var expanded by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val progress by animateFloatAsState(if (shown) 1f else 0f, tween(180), label = "menu")
    val density = LocalDensity.current
    val run: (() -> Unit) -> Unit = { action ->
        onDismiss()
        action()
    }
    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { origin = it.positionInRoot() }) {
        val start = origin ?: return@BoxWithConstraints
        val height = constraints.maxHeight.toFloat()
        fun px(value: Float) = value * density.density
        val margin = px(12f)
        val gap = px(8f)
        val reactionHeight = px(REACTION_HEIGHT)
        val showsMore = more.isNotEmpty() && !expanded
        val items = if (expanded) primary + more else primary
        val menuHeight = px(ROW_HEIGHT * (items.size + if (showsMore) 1 else 0) + 8f + if (showsMore) 9f else 0f)
        val top = WindowInsets.safeDrawing.getTop(density) + margin
        val bottom = height - WindowInsets.safeDrawing.getBottom(density) - margin
        val reactionSpace = if (reactions != null) reactionHeight + gap else 0f
        // Пузырь стоит на своём месте, пока капсула сверху и пункты снизу влезают; иначе
        // сдвигается, а слишком высокий — обрезается сверху вниз.
        val previewHeight = max(px(60f), min(anchor.height, bottom - top - reactionSpace - gap - menuHeight))
        val y = (anchor.top - start.y).coerceAtLeast(top + reactionSpace).coerceAtMost(bottom - menuHeight - gap - previewHeight)
        val side = if (outgoing) Alignment.TopEnd else Alignment.TopStart
        val origin2 = if (outgoing) TransformOrigin(1f, 0f) else TransformOrigin(0f, 0f)

        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = progress }
                .background(Color.Black.copy(alpha = 0.45f))
                .pointerInput(Unit) { detectTapGestures { onDismiss() } }
                .semantics { contentDescription = "Закрыть меню" },
        )
        Box(
            Modifier
                .offset { IntOffset((anchor.left - start.x).roundToInt(), y.roundToInt()) }
                .width(with(density) { anchor.width.toDp() })
                .height(with(density) { previewHeight.toDp() })
                .clipToBounds(),
        ) { preview() }
        if (reactions != null) {
            ReactionCapsule(
                reactions, mine,
                onReact = { emoji -> run { onReact(emoji) } },
                onMore = onMoreReactions?.let { more -> { run(more) } },
                modifier = Modifier
                    .align(side)
                    .offset { IntOffset(0, (y - reactionSpace).roundToInt()) }
                    .padding(horizontal = 12.dp)
                    .graphicsLayer {
                        alpha = progress
                        scaleX = 0.6f + 0.4f * progress
                        scaleY = scaleX
                        transformOrigin = if (outgoing) TransformOrigin(1f, 1f) else TransformOrigin(0f, 1f)
                    },
            )
        }
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shadowElevation = 8.dp,
            modifier = Modifier
                .align(side)
                .offset { IntOffset(0, (y + previewHeight + gap).roundToInt()) }
                .padding(horizontal = 12.dp)
                .width(MENU_WIDTH.dp)
                .graphicsLayer {
                    alpha = progress
                    scaleX = 0.6f + 0.4f * progress
                    scaleY = scaleX
                    transformOrigin = origin2
                },
        ) {
            Column(Modifier.padding(vertical = 4.dp)) {
                items.forEach { item -> MenuRow(item.label, item.icon, item.destructive) { run(item.onClick) } }
                if (showsMore) {
                    HorizontalDivider(Modifier.padding(vertical = 4.dp))
                    MenuRow("Ещё…", Icons.Filled.MoreHoriz, false) { expanded = true }
                }
            }
        }
    }
}

@Composable
private fun ReactionCapsule(
    reactions: List<String>,
    mine: String?,
    onReact: (String) -> Unit,
    onMore: (() -> Unit)?,
    modifier: Modifier,
) {
    Surface(shape = RoundedCornerShape(26.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, shadowElevation = 8.dp, modifier = modifier) {
        Row(
            Modifier.height(REACTION_HEIGHT.dp).padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            reactions.forEach { emoji ->
                Box(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(if (emoji == mine) MaterialTheme.colorScheme.primary.copy(alpha = 0.2f) else Color.Transparent)
                        .clickCursor()
                        .clickable { onReact(emoji) }
                        .semantics { contentDescription = if (emoji == mine) "$emoji, ваша реакция, убрать" else emoji },
                    contentAlignment = Alignment.Center,
                ) { Text(emoji, fontSize = 26.sp) }
            }
            if (onMore != null) {
                Box(
                    Modifier
                        .size(44.dp)
                        .clickCursor()
                        .clickable(onClick = onMore)
                        .semantics { contentDescription = "Ещё реакции" },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.size(36.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Filled.Add, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
        }
    }
}

@Composable
private fun MenuRow(label: String, icon: ImageVector, destructive: Boolean, onClick: () -> Unit) {
    val color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier
            .fillMaxWidth()
            .height(ROW_HEIGHT.dp)
            .clickCursor()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Text(label, color = color, style = MaterialTheme.typography.bodyLarge)
    }
}

private const val REACTION_HEIGHT = 52f
private const val ROW_HEIGHT = 46f
private const val MENU_WIDTH = 240
