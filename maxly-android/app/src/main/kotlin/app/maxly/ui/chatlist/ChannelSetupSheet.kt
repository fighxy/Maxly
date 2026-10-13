package app.maxly.ui.chatlist

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.BusinessCenter
import androidx.compose.material.icons.outlined.Celebration
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.chatlist.ChannelPublicNotice
import app.maxly.presentation.chatlist.ChannelSetupModel
import app.maxly.presentation.chatlist.ChannelSetupState
import app.maxly.presentation.chatlist.ChannelSetupStep
import app.maxly.presentation.chatlist.ChatListItem
import app.maxly.presentation.contacts.ContactsViewModel
import app.maxly.ui.components.Avatar
import kotlinx.coroutines.delay

/**
 * Настройка нового канала, как в Max: «Приватный канал создан» (тип, ссылка-приглашение,
 * «Скопировать ссылку», «Отправить в MAX», «Продолжить»), затем «Выберите подписчиков».
 * Закончили или отменили — [onDone] открывает канал.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelSetupSheet(model: ChannelSetupModel, shareTargets: List<ChatListItem>, onDone: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.done) { if (state.done) onDone() }
    LaunchedEffect(state.notice) {
        if (state.notice == null) return@LaunchedEffect
        delay(2500)
        model.consumeNotice()
    }
    var sending by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = model::skip, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 20.dp)) {
            when (state.step) {
                ChannelSetupStep.TYPE -> TypeStep(state, model) { sending = true }
                ChannelSetupStep.SUBSCRIBERS -> Subscribers(state, model)
            }
            state.notice?.let {
                Text(it, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp).fillMaxWidth(), textAlign = TextAlign.Center)
            }
        }
    }
    state.publicNotice?.let { kind -> PublicNotice(kind, model::dismissPublic) }
    if (sending) {
        app.maxly.ui.chat.ForwardPicker(
            targets = shareTargets,
            onPick = { target -> sending = false; model.sendLink(target) },
            onDismiss = { sending = false },
            title = "Отправить в MAX",
        )
    }
}

@Composable
private fun TypeStep(state: ChannelSetupState, model: ChannelSetupModel, onSend: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    val copy: () -> Unit = {
        state.link?.let {
            clipboard.setText(AnnotatedString(it))
            model.linkCopied()
        }
    }
    Column(Modifier.heightIn(max = 620.dp).verticalScroll(rememberScrollState())) {
        Text("Тип канала и ссылка", style = MaterialTheme.typography.titleMedium, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Icon(Icons.Outlined.Celebration, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(64.dp).align(Alignment.CenterHorizontally))
        Spacer(Modifier.height(12.dp))
        Text("Приватный канал создан", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        Text("Теперь его можно настроить", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth().padding(top = 4.dp), textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Card {
            TypeRow("Приватный", "Канал доступен только по ссылке", selected = true) {}
            TypeRow("Публичный", "Канал можно найти в поиске", selected = false) { model.askPublic() }
            LinkRow(state, model, copy)
        }
        Spacer(Modifier.height(10.dp))
        Card {
            ActionRow(Icons.Outlined.BusinessCenter, "Публичный для бизнеса", "Для юрлиц, ИП, самозанятых и госорганизаций", more = true) {
                model.askPublic(ChannelPublicNotice.BUSINESS)
            }
        }
        Spacer(Modifier.height(10.dp))
        Card {
            ActionRow(Icons.Outlined.ContentCopy, "Скопировать ссылку", enabled = state.link != null) { copy() }
            ActionRow(Icons.AutoMirrored.Outlined.Send, "Отправить в MAX", enabled = state.link != null && !state.busy, onClick = onSend)
        }
    }
    Button(onClick = model::next, modifier = Modifier.fillMaxWidth().padding(top = 16.dp).height(48.dp)) { Text("Продолжить") }
}

@Composable
private fun LinkRow(state: ChannelSetupState, model: ChannelSetupModel, copy: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest) {
            Row(Modifier.fillMaxWidth().padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    state.shortLink ?: "Ссылка появится через секунду…",
                    color = if (state.link != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).clickable(enabled = state.link != null) { copy() },
                )
                Box {
                    IconButton(onClick = { menu = true }, enabled = !state.busy) { Icon(Icons.Outlined.MoreHoriz, "Ещё") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Скопировать ссылку") }, enabled = state.link != null, onClick = { menu = false; copy() })
                        DropdownMenuItem(text = { Text("Сбросить ссылку") }, onClick = { menu = false; model.revokeLink() })
                    }
                }
            }
        }
        Text("Ссылка-приглашение в ваш канал", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp, start = 4.dp))
    }
}

@Composable
private fun Subscribers(state: ChannelSetupState, model: ChannelSetupModel) {
    Text("Выберите подписчиков", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
    OutlinedTextField(
        value = state.query,
        onValueChange = model::setQuery,
        placeholder = { Text("Найти по имени") },
        leadingIcon = { Icon(Icons.Outlined.Search, null) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )
    val now = remember { System.currentTimeMillis() }
    val rows = remember(state.shown) { state.shown.map { ContactsViewModel.rowOf(it, now) } }
    if (rows.isEmpty()) {
        Text(if (state.query.isBlank()) "Контактов пока нет" else "Никого не нашлось", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 16.dp))
    }
    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp).padding(top = 8.dp)) {
        items(rows, key = { it.id }) { row ->
            val picked = row.id in state.selected
            Row(
                Modifier.fillMaxWidth().clickable { model.toggle(row.id) }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Avatar(row.avatar, 44.dp, online = row.isOnline)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(row.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (row.status.isNotEmpty()) {
                        Text(row.status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                }
                RadioButton(selected = picked, onClick = { model.toggle(row.id) })
            }
        }
    }
    Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Button(onClick = model::addSubscribers, enabled = state.selected.isNotEmpty() && !state.busy, modifier = Modifier.weight(1f).height(48.dp)) {
            Text(if (state.selected.isEmpty()) "Добавить" else "Добавить (${state.selected.size})")
        }
        OutlinedButton(onClick = model::skip, modifier = Modifier.weight(1f).height(48.dp)) { Text("Отменить") }
    }
}

/** Публичный канал нужен Цифровой ID — он оформляется только в мобильном приложении MAX. */
@Composable
private fun PublicNotice(kind: ChannelPublicNotice, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                when (kind) {
                    ChannelPublicNotice.PUBLIC -> "Для создания публичного канала нужен Цифровой ID"
                    ChannelPublicNotice.BUSINESS -> "Публичный канал для бизнеса"
                },
            )
        },
        text = {
            Text(
                when (kind) {
                    ChannelPublicNotice.PUBLIC -> "С ним вы сможете создать до 5 публичных каналов. Для создания Цифрового ID перейдите в мобильное приложение MAX."
                    ChannelPublicNotice.BUSINESS -> "Для юрлиц, ИП, самозанятых и госорганизаций. Подключается в мобильном приложении MAX."
                },
            )
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Понятно") } },
    )
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 4.dp)) { content() }
    }
}

@Composable
private fun TypeRow(title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            if (selected) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ActionRow(icon: ImageVector, title: String, subtitle: String? = null, more: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(horizontal = 12.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline)
            subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        if (more) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.outline)
    }
}
