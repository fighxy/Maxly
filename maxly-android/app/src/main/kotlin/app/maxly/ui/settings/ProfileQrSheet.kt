package app.maxly.ui.settings

import android.content.ClipData
import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.maxly.presentation.settings.ProfileLink

/**
 * Лист со ссылкой на профиль: QR-код, сама ссылка (выделяется), «Поделиться» и «Скопировать».
 * [invite] — «Пригласить друзей»: делится текстом приглашения.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileQrSheet(link: String, title: String, invite: Boolean, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val modules = remember(link) { runCatching { ProfileLink.qr(link) }.getOrNull() }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 24.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(16.dp))
            if (modules != null) {
                // Чёрный на белом с полями: читается и в тёмной теме.
                Box(Modifier.clip(RoundedCornerShape(20.dp)).background(Color.White).padding(12.dp)) {
                    Canvas(Modifier.size(220.dp)) {
                        val cell = size.width / modules.size
                        modules.forEachIndexed { y, row ->
                            row.forEachIndexed { x, dark ->
                                if (dark) drawRect(Color.Black, Offset(x * cell, y * cell), Size(cell + 0.5f, cell + 0.5f))
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
            SelectionContainer {
                Text(link, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary, textAlign = TextAlign.Center)
            }
            Spacer(Modifier.height(20.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    onClick = {
                        val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)
                        clipboard?.setPrimaryClip(ClipData.newPlainText("Ссылка", link))
                        android.widget.Toast.makeText(context, "Ссылка скопирована", android.widget.Toast.LENGTH_SHORT).show()
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Outlined.ContentCopy, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Скопировать")
                }
                Button(
                    onClick = {
                        val text = if (invite) ProfileLink.inviteText(link) else link
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                        context.startActivity(Intent.createChooser(send, "Поделиться"))
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Outlined.Share, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Поделиться")
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}
