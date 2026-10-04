package app.orbitle.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.orbitle.domain.AccountLimits
import app.orbitle.presentation.settings.AccountLimitsContent

/**
 * Ограничения аккаунта: после входа по коду или паролю и после регистрации, а из настроек —
 * пока ограничения входа действуют. Тексты готовит [app.orbitle.presentation.settings.AccountLimitsText].
 */
@Composable
fun AccountLimitsNotice(content: AccountLimitsContent, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                if (content.entry == AccountLimits.Entry.LOGIN) Icons.Outlined.Lock else Icons.Outlined.HourglassEmpty,
                contentDescription = null,
            )
        },
        title = { Text(content.title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(content.message)
                content.items.forEach { item ->
                    Spacer(Modifier.height(14.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Icon(
                            item.icon.vector,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 2.dp).size(22.dp),
                        )
                        Column {
                            Text(item.title, fontWeight = FontWeight.SemiBold)
                            Text(
                                item.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Понятно") }
        },
    )
}

private val AccountLimitsContent.Icon.vector: ImageVector
    get() = when (this) {
        AccountLimitsContent.Icon.PASSWORD -> Icons.Outlined.Key
        AccountLimitsContent.Icon.SESSIONS -> Icons.Outlined.Devices
        AccountLimitsContent.Icon.MESSAGES -> Icons.Outlined.ChatBubbleOutline
        AccountLimitsContent.Icon.GROUPS -> Icons.Outlined.Group
        AccountLimitsContent.Icon.OTHER -> Icons.Outlined.Schedule
    }
