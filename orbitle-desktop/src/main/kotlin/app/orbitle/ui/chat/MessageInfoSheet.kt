package app.orbitle.ui.chat

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import app.orbitle.ui.components.AppSheet
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.presentation.chat.MessageInfoModel
import app.orbitle.presentation.chat.MessageInfoState
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.ui.components.Avatar

/** «Сведения»: время отправки, правка, пересылка; в группе — «Кем прочитано». */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageInfoSheet(model: MessageInfoModel, onDismiss: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    AppSheet(onDismissRequest = onDismiss) {
        Text(
            model.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
        )
        model.rows.forEach { row ->
            ListItem(
                headlineContent = { Text(row.label) },
                supportingContent = row.value.takeIf { it.isNotEmpty() }?.let { value -> { Text(value) } },
                colors = colors,
            )
        }
        if (state.phase == MessageInfoState.Phase.Unavailable) return@AppSheet
        HorizontalDivider(Modifier.padding(vertical = 4.dp))
        Text(
            "Кем прочитано",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
        )
        Box(Modifier.fillMaxWidth().heightIn(min = 120.dp, max = 480.dp)) {
            when (state.phase) {
                MessageInfoState.Phase.Loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                MessageInfoState.Phase.Failed -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Не удалось загрузить список", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = model::load, modifier = Modifier.padding(top = 12.dp)) { Text("Повторить") }
                }
                MessageInfoState.Phase.Loaded -> {
                    state.emptyText?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.align(Alignment.Center)) }
                    LazyColumn(Modifier.fillMaxWidth()) {
                        items(state.readers, key = { it.userId }) { reader ->
                            val name = MessageInfoModel.name(reader)
                            val initials = ChatAvatar.initials(name)
                            ListItem(
                                headlineContent = { Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                supportingContent = model.readText(reader)?.let { text -> { Text(text, maxLines = 1) } },
                                leadingContent = {
                                    Avatar(
                                        ChatAvatar(reader.avatarUrl?.let { ChatAvatar.Kind.Photo(it, initials) } ?: ChatAvatar.Kind.Initials(initials), ChatAvatar.colorIndex(reader.userId)),
                                        40.dp,
                                    )
                                },
                                trailingContent = reader.emoji?.let { emoji -> { Text(emoji, fontSize = 22.sp) } },
                                colors = colors,
                            )
                        }
                    }
                }
                MessageInfoState.Phase.Unavailable -> Unit
            }
        }
    }
}
