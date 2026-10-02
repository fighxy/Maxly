package app.orbitle.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.domain.ServerFolder
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.presentation.settings.FoldersViewModel
import app.orbitle.presentation.settings.chatsCount
import app.orbitle.presentation.settings.folderSummary
import app.orbitle.ui.components.Avatar

/**
 * «Папки»: серверные папки чатов. «Все» не меняется, остальные переставляются,
 * переименовываются, удаляются и наполняются чатами.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FoldersScreen(
    model: FoldersViewModel,
    count: (ServerFolder) -> Int,
    candidates: () -> List<ChatListItem>,
    onBack: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    var renaming by remember { mutableStateOf<ServerFolder?>(null) }
    var deleting by remember { mutableStateOf<ServerFolder?>(null) }
    var picking by remember { mutableStateOf<ServerFolder?>(null) }
    var creating by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Папки") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        val folders = state.folders
        if (folders == null) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            folders.firstOrNull { it.isAllChats }?.let { all ->
                item(key = "all") {
                    ListItem(
                        headlineContent = { Text(all.title.ifEmpty { "Все" }) },
                        supportingContent = { Text("Все чаты, кроме архива") },
                        leadingContent = { Icon(Icons.Outlined.Folder, null) },
                        trailingContent = { Text("${count(all)}", color = MaterialTheme.colorScheme.onSurfaceVariant) },
                    )
                    HorizontalDivider()
                }
            }
            if (state.editable.isNotEmpty()) {
                item(key = "header") {
                    Text(
                        "Мои папки",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
                    )
                }
            }
            val editable = state.editable
            items(editable, key = { it.id }) { folder ->
                val index = editable.indexOf(folder)
                FolderRow(
                    folder = folder,
                    count = count(folder),
                    canMoveUp = index > 0,
                    canMoveDown = index < editable.lastIndex,
                    enabled = !state.working,
                    onRename = { renaming = folder },
                    onPick = { picking = folder },
                    onDelete = { deleting = folder },
                    onMove = { model.move(folder, it) },
                )
            }
            if (folders.size > 1) {
                item(key = "footer") {
                    Text(
                        "Папки видны над списком чатов и на других устройствах.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
            item(key = "actions") {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                SettingsItem(Icons.Outlined.CreateNewFolder, "Создать папку", enabled = !state.working) { creating = true }
                if (state.missingTypeFolders.isNotEmpty()) {
                    SettingsItem(
                        Icons.Outlined.Layers,
                        "Добавить папки по типам",
                        subtitle = "«Личные», «Каналы» и «Боты» наполняются сами по типу чата",
                        enabled = !state.working,
                    ) { model.addTypeFolders() }
                }
            }
        }
    }

    renaming?.let { folder ->
        TitleDialog(
            title = "Переименовать папку",
            initial = folder.title,
            onDismiss = { renaming = null },
            onSave = {
                model.rename(folder, it)
                renaming = null
            },
        )
    }
    deleting?.let { folder ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Удалить папку «${folder.title}»?") },
            text = { Text("Чаты останутся в списке «Все».") },
            confirmButton = {
                TextButton(onClick = {
                    model.delete(folder)
                    deleting = null
                }) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Отмена") } },
        )
    }
    picking?.let { folder ->
        FolderChatPicker(
            title = folder.title,
            chats = remember { candidates() },
            initial = folder.chatIds.toSet(),
            askTitle = false,
            onDismiss = { picking = null },
            onDone = { _, ids ->
                model.setChats(folder, ids)
                picking = null
            },
        )
    }
    if (creating) {
        FolderChatPicker(
            title = "Новая папка",
            chats = remember { candidates() },
            initial = emptySet(),
            askTitle = true,
            onDismiss = { creating = false },
            onDone = { title, ids ->
                model.create(title, ids)
                creating = false
            },
        )
    }
    state.error?.let {
        AlertDialog(
            onDismissRequest = model::dismissError,
            title = { Text("Не получилось") },
            text = { Text(it) },
            confirmButton = { TextButton(onClick = model::dismissError) { Text("OK") } },
        )
    }
}

@Composable
private fun FolderRow(
    folder: ServerFolder,
    count: Int,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    enabled: Boolean,
    onRename: () -> Unit,
    onPick: () -> Unit,
    onDelete: () -> Unit,
    onMove: (Int) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(folder.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        supportingContent = folderSummary(folder, count)?.let { { Text(it) } },
        leadingContent = { Icon(Icons.Outlined.Folder, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        trailingContent = {
            Box {
                IconButton(onClick = { menu = true }, enabled = enabled) { Icon(Icons.Outlined.MoreVert, "Действия с папкой") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Переименовать") }, leadingIcon = { Icon(Icons.Outlined.Edit, null) }, onClick = {
                        menu = false
                        onRename()
                    })
                    DropdownMenuItem(text = { Text("Выбрать чаты") }, leadingIcon = { Icon(Icons.Outlined.Checklist, null) }, onClick = {
                        menu = false
                        onPick()
                    })
                    if (canMoveUp) {
                        DropdownMenuItem(text = { Text("Выше") }, leadingIcon = { Icon(Icons.Outlined.KeyboardArrowUp, null) }, onClick = {
                            menu = false
                            onMove(-1)
                        })
                    }
                    if (canMoveDown) {
                        DropdownMenuItem(text = { Text("Ниже") }, leadingIcon = { Icon(Icons.Outlined.KeyboardArrowDown, null) }, onClick = {
                            menu = false
                            onMove(1)
                        })
                    }
                    DropdownMenuItem(
                        text = { Text("Удалить", color = MaterialTheme.colorScheme.error) },
                        leadingIcon = { Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error) },
                        onClick = {
                            menu = false
                            onDelete()
                        },
                    )
                }
            }
        },
        modifier = Modifier.clickable(enabled = enabled, onClick = onPick),
    )
}

@Composable
private fun TitleDialog(title: String, initial: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Название") }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onSave(text) }, enabled = text.isNotBlank()) { Text("Сохранить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

/** Выбор чатов папки: весь список с галочками и поиском. Для новой папки — ещё и название. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FolderChatPicker(
    title: String,
    chats: List<ChatListItem>,
    initial: Set<String>,
    askTitle: Boolean,
    onDismiss: () -> Unit,
    onDone: (String, List<String>) -> Unit,
) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val selection = remember { mutableStateListOf<String>().apply { addAll(chats.map { it.id }.filter { it in initial }) } }
    var name by remember { mutableStateOf("") }
    var query by remember { mutableStateOf("") }
    val shown = remember(chats, query) {
        val text = query.trim()
        if (text.isEmpty()) chats else chats.filter { it.title.contains(text, ignoreCase = true) }
    }
    val canSave = !askTitle || name.isNotBlank()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(Modifier.fillMaxWidth()) {
            androidx.compose.foundation.layout.Row(
                Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                TextButton(onClick = { onDone(name.trim(), selection.toList()) }, enabled = canSave) { Text("Готово") }
            }
            if (askTitle) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Название") },
                    placeholder = { Text("Например, Работа") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("Поиск чата") },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                singleLine = true,
                shape = RoundedCornerShape(28.dp),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
            Text(
                if (selection.isEmpty()) "Чаты не выбраны" else "Выбрано: ${chatsCount(selection.size)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 24.dp),
            )
            LazyColumn(Modifier.fillMaxWidth().fillMaxHeight(0.8f)) {
                items(shown, key = { it.id }) { item ->
                    val checked = item.id in selection
                    val toggle = { if (checked) selection.remove(item.id) else selection.add(item.id) }
                    ListItem(
                        headlineContent = { Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        leadingContent = { Avatar(item.avatar, 40.dp) },
                        trailingContent = { Checkbox(checked = checked, onCheckedChange = { toggle() }) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.clickable { toggle() },
                    )
                }
            }
        }
    }
}
