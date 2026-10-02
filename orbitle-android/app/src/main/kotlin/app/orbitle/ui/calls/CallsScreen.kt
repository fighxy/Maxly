package app.orbitle.ui.calls

import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import app.orbitle.presentation.calls.CallRow
import app.orbitle.presentation.calls.CallsFilter
import app.orbitle.presentation.calls.CallsUiState
import app.orbitle.presentation.calls.CallsViewModel
import app.orbitle.ui.chatlist.Placeholder
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.privateBlur

private val MissedRed = Color(0xFFE5484D)

/** Вкладка «Звонки»: «Все» и «Пропущенные», нажатие открывает чат с собеседником. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallsScreen(model: CallsViewModel, onOpenChat: (String) -> Unit) {
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
                            CallRowItem(row, onOpen = { row.chatId?.let(onOpenChat) }, onHide = { model.hide(row) })
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CallRowItem(row: CallRow, onOpen: () -> Unit, onHide: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val hidden = privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER
    Box {
        ListItem(
            leadingContent = { Avatar(if (hidden) app.orbitle.presentation.settings.PrivateModeMask.avatar(row.avatar) else row.avatar, 48.dp, modifier = Modifier.privateBlur(privacy, 8.dp)) },
            headlineContent = {
                Text(if (hidden) app.orbitle.presentation.settings.PrivateModeMask.callTitle(row.isGroup) else row.title, modifier = Modifier.privateBlur(privacy, 7.dp), maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (row.isMissed) MissedRed else MaterialTheme.colorScheme.onSurface)
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
                    if (row.isVideo) {
                        Spacer(Modifier.width(8.dp))
                        Icon(Icons.Filled.Videocam, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            },
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
            modifier = Modifier.combinedClickable(onClick = onOpen, onLongClick = { menu = true }),
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text("Убрать из истории") },
                leadingIcon = { Icon(Icons.Outlined.DeleteOutline, null) },
                onClick = {
                    menu = false
                    onHide()
                },
            )
        }
    }
}
