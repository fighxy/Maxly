package app.maxly.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import app.maxly.ui.components.AppSheet
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.chat.ReactionUsersModel
import app.maxly.presentation.chat.ReactionUsersState
import app.maxly.presentation.chatlist.ChatAvatar
import app.maxly.ui.components.Avatar

/** «Кто отреагировал»: вкладки по реакциям и список людей. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReactionUsersSheet(model: ReactionUsersModel, onDismiss: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    AppSheet(onDismissRequest = onDismiss, wide = true) {
        Text(
            model.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
        )
        if (model.tabs.size > 1) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(selected = state.filter == null, onClick = { model.select(null) }, label = { Text("Все") })
                model.tabs.forEach { reaction ->
                    FilterChip(
                        selected = state.filter == reaction.emoji,
                        onClick = { model.select(reaction.emoji) },
                        label = { Text("${reaction.emoji} ${reaction.count}") },
                    )
                }
            }
        }
        Box(Modifier.fillMaxWidth().heightIn(min = 160.dp, max = 520.dp)) {
            when (state.phase) {
                ReactionUsersState.Phase.Loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                ReactionUsersState.Phase.Failed -> androidx.compose.foundation.layout.Column(
                    Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("Не удалось загрузить список", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = model::load, modifier = Modifier.padding(top = 12.dp)) { Text("Повторить") }
                }
                ReactionUsersState.Phase.Loaded -> {
                    state.emptyText?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.align(Alignment.Center)) }
                    LazyColumn(Modifier.fillMaxWidth()) {
                        items(state.visible, key = { it.userId + it.emoji }) { user ->
                            val name = ReactionUsersModel.name(user)
                            val initials = ChatAvatar.initials(name)
                            ListItem(
                                headlineContent = { Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                leadingContent = {
                                    Avatar(
                                        ChatAvatar(user.avatarUrl?.let { ChatAvatar.Kind.Photo(it, initials) } ?: ChatAvatar.Kind.Initials(initials), ChatAvatar.colorIndex(user.userId)),
                                        40.dp,
                                    )
                                },
                                trailingContent = { Text(user.emoji, fontSize = 22.sp) },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Все реакции сервера сеткой: своя подсвечена. */
@Composable
fun ReactionGrid(catalog: List<String>, mine: String?, onPick: (String) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(52.dp),
        modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp).padding(horizontal = 12.dp),
    ) {
        items(catalog, key = { it }) { emoji ->
            Box(
                Modifier
                    .padding(2.dp)
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(if (emoji == mine) MaterialTheme.colorScheme.primary.copy(alpha = 0.2f) else Color.Transparent)
                    .clickable { onPick(emoji) },
                contentAlignment = Alignment.Center,
            ) { Text(emoji, fontSize = 26.sp) }
        }
    }
}
