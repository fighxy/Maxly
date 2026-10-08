package app.orbitle.ui.chat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import app.orbitle.ui.components.AppSheet
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.privateBlur

/** Выбор чата для пересылки: поиск по названию и список чатов. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForwardPicker(targets: List<ChatListItem>, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val shown = remember(targets, query) {
        val text = query.trim()
        if (text.isEmpty()) targets else targets.filter { it.title.contains(text, ignoreCase = true) }
    }
    AppSheet(onDismissRequest = onDismiss, wide = true) {
        Text(
            "Переслать",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
        )
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text("Поиск чата") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            singleLine = true,
            shape = RoundedCornerShape(28.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (shown.isEmpty()) {
            Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                Text(
                    if (targets.isEmpty()) "Нет чатов для пересылки" else "Ничего не найдено",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
            items(shown, key = { it.id }) { original ->
                val item = if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) app.orbitle.presentation.settings.PrivateModeMask.item(original) else original
                ListItem(
                    headlineContent = { Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.privateBlur(privacy, 7.dp)) },
                    leadingContent = { Avatar(item.avatar, 44.dp, modifier = Modifier.privateBlur(privacy, 8.dp)) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickable { onPick(item.id) },
                )
            }
        }
    }
}
