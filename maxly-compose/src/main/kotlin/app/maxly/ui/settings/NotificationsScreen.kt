package app.maxly.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * «Уведомления и звук»: звонки и сообщения, пока приложение свёрнуто. [explanation] — что
 * именно делает переключатель на этой платформе; [blocked] — системный запрет уведомлений
 * с кнопкой [onOpenSystemSettings].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationsScreen(
    enabled: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    explanation: String,
    onBack: (() -> Unit)?,
    blocked: String? = null,
    onOpenSystemSettings: (() -> Unit)? = null,
    /** Пункты платформы под основным переключателем (десктоп: трей и звук). */
    extra: @Composable ColumnScope.() -> Unit = {},
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Уведомления и звук") },
                navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            ListItem(
                headlineContent = { Text("Звонки и сообщения в фоне") },
                trailingContent = { Switch(checked = enabled, onCheckedChange = onEnabledChange) },
                modifier = Modifier.clickable { onEnabledChange(!enabled) },
            )
            Text(
                explanation,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            if (enabled && blocked != null) {
                Text(
                    blocked,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp),
                )
                if (onOpenSystemSettings != null) {
                    TextButton(onClick = onOpenSystemSettings, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Открыть настройки") }
                }
            }
            extra()
        }
    }
}
