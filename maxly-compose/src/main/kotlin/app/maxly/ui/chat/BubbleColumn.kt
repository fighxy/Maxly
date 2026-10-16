package app.maxly.ui.chat

// Колонка содержимого пузыря. Общая для Android и десктопа.
// Ширина — как у обычной Column (самый широкий блок). Блок с [BubbleColumn.FILL]
// дотягивается до этой ширины, чтобы время в нём встало в правый нижний угол пузыря.

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.unit.Constraints
import app.maxly.presentation.chat.BubbleMetaLayout

object BubbleColumn {
    /** Блок, который тянется до ширины пузыря (текст со временем). */
    const val FILL = "bubble-fill"
    /** Блок, прижатый к правому краю. */
    const val END = "bubble-end"
}

@Composable
fun BubbleColumn(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val placeables = arrayOfNulls<Placeable>(measurables.size)
        measurables.forEachIndexed { i, m -> if (m.layoutId != BubbleColumn.FILL) placeables[i] = m.measure(loose) }
        val others = placeables.filterNotNull().map { it.width }
        val maxW = if (constraints.hasBoundedWidth) constraints.maxWidth else Int.MAX_VALUE
        val fill = BubbleMetaLayout.fillWidth(others, maxW)
        measurables.forEachIndexed { i, m ->
            if (m.layoutId == BubbleColumn.FILL) placeables[i] = m.measure(Constraints(minWidth = fill, maxWidth = constraints.maxWidth, maxHeight = loose.maxHeight))
        }
        val all = placeables.map { it!! }
        val width = maxOf(BubbleMetaLayout.bubbleWidth(all.map { it.width }, maxW), constraints.minWidth)
        val height = all.sumOf { it.height }.coerceAtLeast(constraints.minHeight)
        layout(width, height) {
            var y = 0
            all.forEachIndexed { i, p ->
                val x = if (measurables[i].layoutId == BubbleColumn.END) width - p.width else 0
                p.placeRelative(x, y)
                y += p.height
            }
        }
    }
}
