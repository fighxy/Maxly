package app.orbitle.ui.settings

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.material.icons.filled.DragHandle
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
import androidx.compose.material3.OutlinedTextField
import app.orbitle.ui.components.AppSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.zIndex
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.domain.ServerFolder
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.ui.components.DragReorder
import app.orbitle.presentation.settings.FoldersViewModel
import app.orbitle.presentation.settings.chatsCount
import app.orbitle.presentation.settings.folderSummary
import app.orbitle.ui.components.Avatar
import kotlinx.coroutines.launch

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
    val listState = rememberLazyListState()
    val drag = remember(listState) { DragReorder(listState) }
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val currentEditable by rememberUpdatedState(state.editable)
    val editableIds = { currentEditable.map { it.id } }
    // Отпустили: порядок уходит в модель один раз, строка доезжает до своего места.
    val drop = {
        drag.finish()?.let(model::reorder)
        scope.launch { drag.settle() }
        Unit
    }
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
        LazyColumn(Modifier.padding(padding).fillMaxSize(), state = listState) {
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
            val byId = editable.associateBy { it.id }
            // Во время перетаскивания — рабочий порядок экрана, иначе порядок сервера.
            val shown = drag.order?.mapNotNull(byId::get) ?: editable
            items(shown, key = { it.id }) { folder ->
                val index = shown.indexOf(folder)
                val dragged = drag.draggedId == folder.id
                FolderRow(
                    folder = folder,
                    count = count(folder),
                    canMoveUp = index > 0,
                    canMoveDown = index < shown.lastIndex,
                    enabled = !state.working,
                    dragged = dragged,
                    onRename = { renaming = folder },
                    onPick = { picking = folder },
                    onDelete = { deleting = folder },
                    onMove = { model.move(folder, it) },
                    dragGestures = {
                        detectDragGestures(
                            onDragStart = {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                drag.start(folder.id, editableIds())
                            },
                            onDrag = { change, amount ->
                                change.consume()
                                drag.drag(amount.y)
                            },
                            onDragEnd = { drop() },
                            onDragCancel = { drop() },
                        )
                    },
                    modifier = if (dragged) {
                        Modifier.zIndex(1f).graphicsLayer { translationY = drag.offset }
                    } else {
                        Modifier.animateItem(fadeInSpec = null, fadeOutSpec = null)
                    },
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
    dragged: Boolean,
    onRename: () -> Unit,
    onPick: () -> Unit,
    onDelete: () -> Unit,
    onMove: (Int) -> Unit,
    /** Жесты ручки перетаскивания. */
    dragGestures: suspend PointerInputScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    var menu by remember { mutableStateOf(false) }
    val elevation by animateDpAsState(if (dragged) 6.dp else 0.dp, label = "folderDragElevation")
    // Перекомпоновка во время перетаскивания не должна перезапускать жест.
    val gestures by rememberUpdatedState(dragGestures)
    ListItem(
        headlineContent = { Text(folder.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        supportingContent = folderSummary(folder, count)?.let { { Text(it) } },
        leadingContent = { Icon(Icons.Outlined.Folder, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
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
                // Ручка: потянуть вверх или вниз, чтобы поменять порядок. Для TalkBack — действия строки.
                Box(
                    Modifier.size(48.dp).then(if (enabled) Modifier.pointerInput(folder.id) { gestures(this) } else Modifier),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.DragHandle,
                        null,
                        tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                    )
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = if (dragged) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surface),
        tonalElevation = elevation,
        shadowElevation = elevation,
        modifier = modifier.clickable(enabled = enabled, onClick = onPick).semantics {
            val actions = buildList {
                if (canMoveUp) add(CustomAccessibilityAction("Переместить выше") { onMove(-1); true })
                if (canMoveDown) add(CustomAccessibilityAction("Переместить ниже") { onMove(1); true })
            }
            if (enabled && actions.isNotEmpty()) customActions = actions
        },
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
    val selection = remember { mutableStateListOf<String>().apply { addAll(chats.map { it.id }.filter { it in initial }) } }
    var name by remember { mutableStateOf("") }
    var query by remember { mutableStateOf("") }
    val shown = remember(chats, query) {
        val text = query.trim()
        if (text.isEmpty()) chats else chats.filter { it.title.contains(text, ignoreCase = true) }
    }
    val canSave = !askTitle || name.isNotBlank()
    AppSheet(onDismissRequest = onDismiss, wide = true) {
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
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 420.dp)) {
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
