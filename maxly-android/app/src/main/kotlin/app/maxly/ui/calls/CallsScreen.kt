package app.maxly.ui.calls

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.filled.AddLink
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.calls.CallRow
import app.maxly.presentation.calls.CallsFilter
import app.maxly.presentation.calls.CallsUiState
import app.maxly.presentation.calls.CallsViewModel
import app.maxly.ui.calls.CallLinkDialog
import app.maxly.ui.chatlist.Placeholder
import app.maxly.ui.components.Avatar
import app.maxly.ui.components.clickCursor
import app.maxly.ui.components.onSecondaryClick
import app.maxly.ui.components.privateBlur

private val MissedRed = Color(0xFFE5484D)

/** Вкладка «Звонки»: «Все» и «Пропущенные», нажатие открывает чат с собеседником. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallsScreen(
    model: CallsViewModel,
    onOpenChat: (String) -> Unit,
    /** Войти в групповой звонок по ссылке. */
    onJoin: (String) -> Unit = {},
    /** Перезвонить: строка и видео ли. */
    onCall: (CallRow, Boolean) -> Unit = { _, _ -> },
    /** Поделиться ссылкой через систему; `null` — только скопировать. */
    onShareLink: ((String) -> Unit)? = null,
) {
    var joining by remember { mutableStateOf(false) }
    val state by model.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    DisposableEffect(Unit) {
        model.appeared()
        onDispose { model.disappeared() }
    }
    LaunchedEffect(state.error) {
        val error = state.error ?: return@LaunchedEffect
        snackbar.showSnackbar(error)
        model.dismissError()
    }
    Scaffold(
        topBar = { TopAppBar(title = { Text("Звонки") }) },
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            ActionRow(if (state.isCreatingLink) "Создаём звонок…" else "Создать звонок", Icons.Filled.AddLink, enabled = !state.isCreatingLink, onClick = model::createLink)
            ActionRow("Присоединиться", Icons.Filled.GroupAdd) { joining = true }
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
                CallsFilter.entries.forEachIndexed { index, filter ->
                    SegmentedButton(
                        selected = state.filter == filter,
                        onClick = { model.setFilter(filter) },
                        shape = SegmentedButtonDefaults.itemShape(index, CallsFilter.entries.size),
                    ) { Text(filter.title) }
                }
            }
            PullToRefreshBox(isRefreshing = state.isRefreshing && state.content != CallsUiState.Content.LOADING, onRefresh = model::refresh, modifier = Modifier.weight(1f)) {
                when (state.content) {
                    CallsUiState.Content.LOADING -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    CallsUiState.Content.EMPTY -> LazyColumn(Modifier.fillMaxSize()) {
                        item {
                            Box(Modifier.fillParentMaxSize()) {
                                Placeholder(
                                    icon = { Icon(Icons.Outlined.Call, null, Modifier.size(56.dp)) },
                                    title = if (state.filter == CallsFilter.MISSED) "Пропущенных звонков нет" else "Звонков пока нет",
                                )
                            }
                        }
                    }
                    CallsUiState.Content.READY -> LazyColumn(Modifier.fillMaxSize()) {
                        items(state.rows, key = { it.id }) { row ->
                            CallRowItem(row, onOpen = { row.chatId?.let(onOpenChat) }, onDelete = { model.delete(row) }, onCall = { onCall(row, row.isVideo) })
                        }
                    }
                }
            }
        }
    }
    state.createdLink?.let { link ->
        CallLinkDialog(
            link,
            onJoin = { onJoin(link) },
            onShare = onShareLink,
            onDismiss = model::dismissLink,
        )
    }
    if (joining) JoinCallDialog(onJoin = { joining = false; onJoin(it) }, onDismiss = { joining = false })
}

/** «Присоединиться»: ссылка на звонок или её токен. */
@Composable
private fun JoinCallDialog(onJoin: (String) -> Unit, onDismiss: () -> Unit) {
    var link by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Присоединиться к звонку") },
        text = {
            OutlinedTextField(link, { link = it }, placeholder = { Text("Ссылка на звонок") }, singleLine = true)
        },
        confirmButton = {
            TextButton(onClick = { link.trim().takeIf { it.isNotEmpty() }?.let(onJoin) }, enabled = link.isNotBlank()) { Text("Войти") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

@Composable
private fun ActionRow(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean = true, onClick: () -> Unit) {
    ListItem(
        leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        headlineContent = { Text(title, color = MaterialTheme.colorScheme.primary) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickCursor().clickable(enabled = enabled, onClick = onClick),
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CallRowItem(row: CallRow, onOpen: () -> Unit, onDelete: () -> Unit, onCall: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val privacy = app.maxly.ui.components.LocalPrivateMode.current
    val hidden = privacy == app.maxly.domain.PrivateModeDisplay.PLACEHOLDER
    Box {
        ListItem(
            leadingContent = { Avatar(if (hidden) app.maxly.presentation.settings.PrivateModeMask.avatar(row.avatar) else row.avatar, 48.dp, modifier = Modifier.privateBlur(privacy, 8.dp)) },
            headlineContent = {
                Text(if (hidden) app.maxly.presentation.settings.PrivateModeMask.callTitle(row.isGroup) else row.title, modifier = Modifier.privateBlur(privacy, 7.dp), maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (row.isMissed) MissedRed else MaterialTheme.colorScheme.onSurface)
            },
            supportingContent = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val icon = when (row.direction) {
                        CallRow.Direction.OUTGOING -> Icons.AutoMirrored.Filled.CallMade
                        CallRow.Direction.INCOMING -> Icons.AutoMirrored.Filled.CallReceived
                        CallRow.Direction.DOWN -> Icons.Filled.CallEnd
                    }
                    Icon(icon, null, Modifier.size(16.dp), tint = if (row.isMissed) MissedRed else MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(4.dp))
                    Text(row.status, maxLines = 1)
                }
            },
            trailingContent = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(row.dateText, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    // Перезвонить тем же видом звонка, как на iOS.
                    if (!row.isGroup && row.peerId.isNotEmpty()) {
                        IconButton(onClick = onCall) {
                            Icon(
                                if (row.isVideo) Icons.Filled.Videocam else Icons.Outlined.Call,
                                if (row.isVideo) "Видеозвонок" else "Позвонить",
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            },
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
            modifier = Modifier.onSecondaryClick { menu = true }.combinedClickable(onClick = onOpen, onLongClick = { menu = true }),
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text("Удалить из истории") },
                leadingIcon = { Icon(Icons.Outlined.DeleteOutline, null) },
                onClick = {
                    menu = false
                    onDelete()
                },
            )
        }
    }
}
