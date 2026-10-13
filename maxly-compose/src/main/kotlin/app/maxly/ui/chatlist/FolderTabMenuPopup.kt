package app.maxly.ui.chatlist

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DoneAll
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
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
import androidx.compose.ui.graphics.vector.ImageVector
import app.maxly.presentation.chatlist.FolderTabMenu.Entry

/**
 * Меню вкладки папки ([app.maxly.presentation.chatlist.FolderTabMenu]) под самой вкладкой:
 * пункты по порядку, «Удалить» красным, перед «Изменить порядок» — разделитель.
 */
@Composable
fun FolderTabMenuPopup(entries: List<Entry>, expanded: Boolean, onDismiss: () -> Unit, onPick: (Entry) -> Unit) {
    DropdownMenu(expanded = expanded && entries.isNotEmpty(), onDismissRequest = onDismiss) {
        val error = MaterialTheme.colorScheme.error
        entries.forEach { entry ->
            if (entry.separated) HorizontalDivider()
            DropdownMenuItem(
                text = { Text(entry.title) },
                leadingIcon = { Icon(icon(entry), null) },
                colors = if (entry.isDanger) MenuDefaults.itemColors(textColor = error, leadingIconColor = error) else MenuDefaults.itemColors(),
                onClick = {
                    onDismiss()
                    onPick(entry)
                },
            )
        }
    }
}

private fun icon(entry: Entry): ImageVector = when (entry) {
    Entry.EditFolders, Entry.EditFolder -> Icons.Outlined.Edit
    Entry.AddChats -> Icons.Outlined.Add
    Entry.ReadAll -> Icons.Outlined.DoneAll
    is Entry.Mute -> if (entry.muted) Icons.Outlined.NotificationsActive else Icons.Outlined.NotificationsOff
    Entry.Delete -> Icons.Outlined.Delete
    Entry.Reorder -> Icons.AutoMirrored.Outlined.Sort
}

/** «Удалить папку?» из меню вкладки: чаты остаются во «Все». */
@Composable
fun DeleteFolderDialog(title: String, onDismiss: () -> Unit, onDelete: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Удалить папку «$title»?") },
        text = { Text("Чаты останутся в списке «Все».") },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                onDelete()
            }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}
