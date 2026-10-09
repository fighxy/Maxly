package app.maxly.ui.chatlist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.maxly.presentation.auth.LoginNotice
import app.maxly.ui.components.clickCursor

/**
 * Баннер вверху списка чатов, пока сервер временно не пускает (`login.flood`): его текст (или
 * свой), «Повторить» — снова войти тем же токеном, «Выйти из аккаунта». Список под ним — из
 * сохранённого, без сети.
 */
@Composable
fun LoginNoticeBanner(notice: LoginNotice, onRetry: () -> Unit, onLogout: () -> Unit, modifier: Modifier = Modifier) {
    val content = MaterialTheme.colorScheme.onErrorContainer
    val buttons = ButtonDefaults.textButtonColors(contentColor = content)
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = content,
        modifier = modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        Column(Modifier.padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 4.dp)) {
            Text(notice.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(end = 8.dp))
            notice.message?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 2.dp, end = 8.dp))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onLogout, colors = buttons, modifier = Modifier.clickCursor()) { Text("Выйти из аккаунта") }
                TextButton(onClick = onRetry, colors = buttons, modifier = Modifier.clickCursor()) { Text("Повторить") }
            }
        }
    }
}
