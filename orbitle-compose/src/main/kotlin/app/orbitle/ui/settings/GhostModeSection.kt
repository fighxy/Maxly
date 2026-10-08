package app.orbitle.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DoneAll
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleStartEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.presentation.settings.GhostModeViewModel
import app.orbitle.presentation.settings.GhostModeViewModel.Toggle

/**
 * Блок «Дополнительно» вверху «Конфиденциальности»: возможности Orbitle сверх настроек MAX,
 * отдельной группой со своей подписью. Все переключатели действуют только на этом устройстве.
 */
@Composable
fun GhostModeSection(model: GhostModeViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    Text(
        "Дополнительно",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
    )
    state.toggles.forEach { toggle ->
        val on = state.isOn(toggle)
        ListItem(
            leadingContent = { Icon(icon(toggle), null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
            headlineContent = { Text(state.title(toggle)) },
            supportingContent = { Text(state.subtitle(toggle)) },
            trailingContent = { Switch(on, onCheckedChange = { model.set(toggle, it) }) },
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
            modifier = Modifier.clickable { model.set(toggle, !on) },
        )
    }
    Text(
        "Этих настроек нет в приложении MAX, они действуют только в Orbitle на этом устройстве. " +
            "Режим призрака скрывает, что вы в сети, и не сообщает собеседникам «печатает…», " +
            "«записывает…» или «отправляет…». Если вы сами отправите сообщение или реакцию — " +
            "собеседник это увидит. После выключения ничего задним числом не отправляется.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

private fun icon(toggle: Toggle): ImageVector = when (toggle) {
    Toggle.GHOST -> Icons.Outlined.PersonOff
    Toggle.READ_RECEIPTS -> Icons.Outlined.DoneAll
    Toggle.OWN_PRESENCE -> Icons.Outlined.Visibility
}

/**
 * Свой статус под номером в своём профиле и «Обновить». Пока строка на экране и экран
 * не остановлен, модель спрашивает статус раз в 15 секунд; нет статуса — нет и строки.
 */
@Composable
fun OwnPresenceLine(model: GhostModeViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    LifecycleStartEffect(model) {
        model.setProfileVisible(true)
        onStopOrDispose { model.setProfileVisible(false) }
    }
    val line = state.ownLine ?: return
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            line,
            style = MaterialTheme.typography.bodyMedium,
            color = if (state.own?.isOnline == true) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // Без индикатора: опрос каждые 15 секунд мигал бы им. Кнопка гаснет, пока идёт запрос.
        IconButton(onClick = model::refreshOwnPresence, enabled = !state.checking) {
            Icon(Icons.Outlined.Refresh, "Обновить мой статус", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
