package app.maxly.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.maxly.domain.InlineButton
import app.maxly.domain.InlineKeyboard
import app.maxly.domain.LinkPreview
import coil3.compose.AsyncImage

/** «Непрочитанные сообщения» над первым непрочитанным при открытии чата: полоса во всю ширину. */
@Composable
fun UnreadDivider() {
    Box(
        Modifier.fillMaxWidth().padding(vertical = 6.dp).background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.85f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "Непрочитанные сообщения",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 6.dp),
        )
    }
}

/** Превью ссылки (`SHARE`) в пузыре: полоска слева, сайт, заголовок, описание, картинка. Нажатие открывает адрес. */
@Composable
internal fun LinkPreviewCard(preview: LinkPreview, colors: BubbleColors) {
    val uri = LocalUriHandler.current
    Row(
        Modifier
            .padding(start = 10.dp, end = 10.dp, bottom = 8.dp)
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(6.dp))
            .clickable { runCatching { uri.openUri(preview.url) } },
    ) {
        Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(colors.accent))
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            preview.site?.let {
                Text(it, color = colors.accent, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            preview.title?.let {
                Text(it, color = colors.content, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            preview.summary?.let {
                Text(it, color = colors.content.copy(alpha = 0.85f), style = MaterialTheme.typography.bodySmall, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            preview.imageUrl?.let { image ->
                val w = preview.imageWidth
                val h = preview.imageHeight
                val ratio = if (w != null && h != null && w > 0 && h > 0) (w.toFloat() / h).coerceAtLeast(1f) else 16f / 9f
                AsyncImage(
                    image,
                    null,
                    Modifier.padding(top = 4.dp).fillMaxWidth().aspectRatio(ratio).heightIn(max = 180.dp).clip(RoundedCornerShape(8.dp)),
                    contentScale = ContentScale.Crop,
                )
            }
        }
    }
}

/** Inline-кнопки бота под пузырём: ряды кнопок во всю ширину, значок справа — ссылка, приложение, копирование. */
@Composable
internal fun InlineKeyboardView(keyboard: InlineKeyboard, enabled: Boolean, onPress: (InlineButton) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        keyboard.rows.forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                row.forEach { button ->
                    Surface(
                        onClick = { onPress(button) },
                        enabled = enabled,
                        shape = RoundedCornerShape(12.dp),
                        color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.92f),
                        contentColor = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f).heightIn(min = 38.dp),
                    ) {
                        Row(Modifier.padding(horizontal = 8.dp, vertical = 8.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                button.text,
                                style = MaterialTheme.typography.labelLarge,
                                textAlign = TextAlign.Center,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f, fill = false),
                            )
                            val icon = when (button.hint) {
                                InlineButton.Hint.LINK -> Icons.AutoMirrored.Filled.OpenInNew
                                InlineButton.Hint.APP -> Icons.Filled.Apps
                                InlineButton.Hint.COPY -> Icons.Filled.ContentCopy
                                null -> null
                            }
                            if (icon != null) {
                                Spacer(Modifier.width(4.dp))
                                Icon(icon, null, Modifier.size(14.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}
