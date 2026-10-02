package app.orbitle.ui.components

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp

/**
 * Мягкие края ленты: содержимое плавно растворяется у верхнего и нижнего края, и сквозь него
 * видны обои или фон ровно на своём месте — без полосы другого цвета. Отступы и касания
 * не меняются.
 */
fun Modifier.edgeFade(top: Dp, bottom: Dp): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        val t = top.toPx()
        val b = bottom.toPx()
        if (t > 0f) {
            drawRect(
                Brush.verticalGradient(0f to Color.Transparent, 1f to Color.Black, startY = 0f, endY = t),
                size = Size(size.width, t),
                blendMode = BlendMode.DstIn,
            )
        }
        if (b > 0f) {
            // Плавная кривая: почти всё видно, растворяется только у самого края.
            drawRect(
                Brush.verticalGradient(
                    0f to Color.Black, 0.5f to Color.Black.copy(alpha = 0.8f), 1f to Color.Transparent,
                    startY = size.height - b, endY = size.height,
                ),
                topLeft = Offset(0f, size.height - b),
                size = Size(size.width, b),
                blendMode = BlendMode.DstIn,
            )
        }
    }
