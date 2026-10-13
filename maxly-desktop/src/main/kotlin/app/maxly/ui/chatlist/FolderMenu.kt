package app.maxly.ui.chatlist

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import app.maxly.presentation.chatlist.ChatListMenu

/**
 * Подменю «Добавить в папку» внутри открытого меню, как в Max: «Назад», папки (галочка — чат уже
 * там, повтор — убрать), черта и «Создать папку».
 */
@Composable
fun FolderSubmenu(
    folders: List<ChatListMenu.FolderChoice>,
    onBack: () -> Unit,
    onToggle: (String) -> Unit,
    onCreate: () -> Unit,
) {
    DropdownMenuItem(text = { Text("Назад") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.ArrowBack, null) }, onClick = onBack)
    HorizontalDivider()
    folders.forEach { folder ->
        DropdownMenuItem(
            text = { Text(folder.title) },
            leadingIcon = { Icon(Icons.Outlined.Folder, null) },
            trailingIcon = if (folder.contains) ({ Icon(Icons.Filled.Check, "В папке") }) else null,
            onClick = { onToggle(folder.id) },
        )
    }
    if (folders.isNotEmpty()) HorizontalDivider()
    DropdownMenuItem(text = { Text(ChatListMenu.CREATE_FOLDER) }, leadingIcon = { Icon(Icons.Filled.Add, null) }, onClick = onCreate)
}

/** Название новой папки; чат попадает в неё сразу. */
@Composable
fun CreateFolderDialog(onCreate: (String) -> Unit, onDismiss: () -> Unit) {
    var title by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Новая папка") },
        text = {
            OutlinedTextField(title, { title = it.take(40) }, singleLine = true, placeholder = { Text("Название папки") })
        },
        confirmButton = {
            TextButton(onClick = { onCreate(title) }, enabled = title.isNotBlank()) { Text("Создать") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}
