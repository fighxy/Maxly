package app.orbitle.ui.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Высота капсулы звука и круга поиска: одна линия. */
private val ChannelControl = 40.dp

/**
 * Низ канала, где писать нельзя: «Включить звук» / «Выключить звук» по центру,
 * поиск — круг той же высоты справа. Пустой круг слева держит подпись на оси экрана.
 */
@Composable
fun ChannelSoundSearchBar(muted: Boolean, onToggleMute: () -> Unit, onSearch: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Spacer(Modifier.size(ChannelControl))
        FilledTonalButton(
            onClick = onToggleMute,
            modifier = Modifier.height(ChannelControl),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 0.dp),
        ) {
            Icon(
                if (muted) Icons.Outlined.NotificationsActive else Icons.Outlined.NotificationsOff,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(if (muted) "Включить звук" else "Выключить звук")
        }
        FilledTonalButton(
            onClick = onSearch,
            modifier = Modifier.size(ChannelControl),
            shape = CircleShape,
            contentPadding = PaddingValues(0.dp),
        ) {
            Icon(Icons.Filled.Search, contentDescription = "Поиск", modifier = Modifier.size(20.dp))
        }
    }
}
