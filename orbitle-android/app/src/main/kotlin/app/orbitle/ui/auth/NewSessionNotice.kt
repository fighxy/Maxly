package app.orbitle.ui.auth

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * После входа по коду. Сервер не даёт свежему сеансу завершать другие сеансы
 * и менять облачный пароль, отдельного признака в ответе нет.
 */
@Composable
fun NewSessionNotice(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Новый сеанс") },
        text = {
            Column {
                Text("Вы вошли в Max на этом устройстве. Пока сеанс новый, часть настроек безопасности недоступна.")
                Spacer(Modifier.height(14.dp))
                Text("Нельзя завершать другие сеансы", fontWeight = FontWeight.SemiBold)
                Text(
                    "Выйти на других устройствах можно будет позже или с устройства, где вход выполнен давно.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(10.dp))
                Text("Нельзя менять облачный пароль", fontWeight = FontWeight.SemiBold)
                Text(
                    "Смена и отключение пароля станут доступны, когда сеанс перестанет быть новым.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Понятно") }
        },
    )
}
