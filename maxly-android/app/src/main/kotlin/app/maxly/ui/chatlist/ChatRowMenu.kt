package app.maxly.ui.chatlist

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.CleaningServices
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MarkChatRead
import androidx.compose.material.icons.outlined.MarkChatUnread
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import app.maxly.domain.ChatType
import app.maxly.domain.StoryOwner
import app.maxly.presentation.chatlist.ChatListItem
import app.maxly.presentation.chatlist.ChatListMenu
import app.maxly.presentation.chatlist.ChatListMenu.Entry

/** Подменю, открытое вместо основного списка. */
private enum class ChatMenuPage { MAIN, FOLDERS, MUTE }

/**
 * Меню строки списка чатов в порядке Max ([ChatListMenu.entries]). «Добавить в папку» и
 * «Отключить уведомления» открывают подменю на месте основного, «Назад» возвращает к нему.
 * Стирание и удаление спрашивает [onErase], блокировку подтверждает своё окно.
 */
@Composable
fun ChatRowMenu(
    item: ChatListItem,
    expanded: Boolean,
    onDismiss: () -> Unit,
    actions: ChatRowActions,
    canReorderPins: Boolean,
    onErase: (app.maxly.ui.chat.ChatErase) -> Unit,
) {
    var page by remember { mutableStateOf(ChatMenuPage.MAIN) }
    var blocking by remember { mutableStateOf(false) }
    var creatingFolder by remember { mutableStateOf(false) }
    val stories = app.maxly.ui.stories.LocalStoryRings.current
    val owner = storyOwner(item)
    val ring = owner?.let { stories.ringFor(it.id, it.type) }
    val saved = item.id == app.maxly.domain.Chat.SAVED_MESSAGES_ID
    val close = {
        page = ChatMenuPage.MAIN
        onDismiss()
    }
    DropdownMenu(expanded = expanded, onDismissRequest = close) {
        val entries = if (expanded) {
            ChatListMenu.entries(
                item,
                folders = actions.folders(item.id),
                hasStories = ring != null && stories.state.own?.owner?.id != ring.owner.id,
                savedMessages = saved,
                canReorderPins = canReorderPins,
            ).filterNot { it is Entry.Block && actions.block == null }
        } else {
            emptyList()
        }
        when (page) {
            ChatMenuPage.MAIN -> entries.forEach { entry ->
                MenuRow(entry.title, icon(entry), danger = entry.isDanger, more = entry is Entry.Folders || (entry is Entry.Mute && !entry.muted)) {
                    when (entry) {
                        is Entry.Folders -> page = ChatMenuPage.FOLDERS
                        is Entry.Pin -> { close(); actions.pin(item.id) }
                        Entry.ReorderPins -> { close(); actions.reorderPins() }
                        is Entry.Read -> { close(); actions.read(item.id) }
                        is Entry.Mute -> if (entry.muted) { close(); actions.mute(item.id) } else page = ChatMenuPage.MUTE
                        Entry.Erase -> { close(); onErase(app.maxly.ui.chat.ChatErase.CLEAR) }
                        Entry.HideStories -> { close(); if (owner != null) stories.hide(owner, ring?.name.orEmpty()) }
                        Entry.Block -> { close(); blocking = true }
                        Entry.Delete -> { close(); onErase(app.maxly.ui.chat.ChatErase.DELETE) }
                    }
                }
            }
            ChatMenuPage.FOLDERS -> FolderSubmenu(
                folders = (entries.firstOrNull { it is Entry.Folders } as? Entry.Folders)?.folders.orEmpty(),
                onBack = { page = ChatMenuPage.MAIN },
                onToggle = { folderId -> close(); actions.toggleFolder(item.id, folderId) },
                onCreate = { close(); creatingFolder = true },
            )
            ChatMenuPage.MUTE -> {
                MenuRow("Назад", Icons.AutoMirrored.Filled.ArrowBack) { page = ChatMenuPage.MAIN }
                HorizontalDivider()
                ChatListMenu.MuteFor.entries.forEach { choice ->
                    MenuRow(choice.title, null, danger = choice.isDanger) { close(); actions.muteFor(item.id, choice) }
                }
            }
        }
    }
    if (creatingFolder) {
        CreateFolderDialog(
            onCreate = { title -> creatingFolder = false; actions.createFolder(item.id, title) },
            onDismiss = { creatingFolder = false },
        )
    }
    if (blocking) {
        val hidden = app.maxly.ui.components.LocalPrivateMode.current != app.maxly.domain.PrivateModeDisplay.VISIBLE
        AlertDialog(
            onDismissRequest = { blocking = false },
            title = { Text(if (hidden) "Заблокировать пользователя?" else "Заблокировать ${item.title}?") },
            text = { Text("Он не сможет писать вам и звонить. Разблокировать можно в настройках конфиденциальности.") },
            confirmButton = {
                TextButton(onClick = { blocking = false; actions.block?.invoke(item.id) }) {
                    Text("Заблокировать", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { blocking = false }) { Text("Отмена") } },
        )
    }
}

/** Владелец историй чата: собеседник в личном, сам чат у группы и канала. */
private fun storyOwner(item: ChatListItem): StoryOwner? = when (item.type) {
    ChatType.PRIVATE -> item.peerId?.let { StoryOwner(it, StoryOwner.Type.USER) }
    ChatType.GROUP -> StoryOwner(item.id, StoryOwner.Type.CHAT)
    ChatType.CHANNEL -> StoryOwner(item.id, StoryOwner.Type.CHANNEL)
}

private fun icon(entry: Entry): ImageVector = when (entry) {
    is Entry.Folders -> Icons.Outlined.CreateNewFolder
    is Entry.Pin -> Icons.Filled.PushPin
    Entry.ReorderPins -> Icons.Filled.SwapVert
    is Entry.Read -> if (entry.unread) Icons.Outlined.MarkChatRead else Icons.Outlined.MarkChatUnread
    is Entry.Mute -> if (entry.muted) Icons.Outlined.NotificationsActive else Icons.Outlined.NotificationsOff
    Entry.Erase -> Icons.Outlined.CleaningServices
    Entry.HideStories -> Icons.Outlined.VisibilityOff
    Entry.Block -> Icons.Outlined.Block
    Entry.Delete -> Icons.Outlined.Delete
}

@Composable
private fun MenuRow(title: String, icon: ImageVector?, danger: Boolean = false, more: Boolean = false, onClick: () -> Unit) {
    val error = MaterialTheme.colorScheme.error
    DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = icon?.let { { Icon(it, null) } },
        trailingIcon = if (more) ({ Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) }) else null,
        colors = if (danger) MenuDefaults.itemColors(textColor = error, leadingIconColor = error) else MenuDefaults.itemColors(),
        onClick = onClick,
    )
}
