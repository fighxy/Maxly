package app.orbitle.ui.chatlist

import androidx.compose.material.icons.outlined.MarkChatRead
import androidx.compose.material.icons.outlined.MarkChatUnread
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.R
import app.orbitle.domain.DeliveryState
import app.orbitle.presentation.chatlist.ChatBadge
import app.orbitle.presentation.chatlist.ChatListContent
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.presentation.chatlist.ChatListUiState
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.ui.components.Avatar
import coil3.compose.AsyncImage

/** Вкладка «Чаты»: папки, поиск, закреплённые, плашка соединения. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatListScreen(viewModel: ChatListViewModel, onOpenChat: (ChatListItem) -> Unit) {
    LifecycleResumeEffect(viewModel) {
        viewModel.reloadLocal()
        onPauseOrDispose {}
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val message by viewModel.messages.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }
    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            Column {
                if (state.isSearchActive) {
                    SearchBarRow(state.searchQuery, viewModel::setSearchQuery) { viewModel.setSearchActive(false) }
                } else {
                    TopAppBar(
                        title = { Text(state.banner ?: stringResource(R.string.chats_title)) },
                        actions = {
                            IconButton(onClick = { viewModel.setSearchActive(true) }) {
                                Icon(Icons.Filled.Search, contentDescription = stringResource(R.string.chats_search))
                            }
                        },
                        scrollBehavior = scroll,
                    )
                }
                if (state.showsFolders && !state.isSearchActive) FolderTabs(state, viewModel::selectFolder)
            }
        },
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.isRefreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            when (val content = state.content) {
                ChatListContent.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                ChatListContent.List -> ChatList(
                    state,
                    onOpenChat = {
                        viewModel.opened(it.id)
                        onOpenChat(it)
                    },
                    actions = ChatRowActions(viewModel::togglePin, viewModel::toggleRead, viewModel::toggleMute),
                )
                ChatListContent.Empty -> Placeholder(
                    icon = { Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.size(56.dp)) },
                    title = stringResource(if (state.searchQuery.isNotBlank()) R.string.chats_search_empty else R.string.chats_empty),
                    text = if (state.searchQuery.isNotBlank()) null else stringResource(R.string.chats_empty_hint),
                )
                ChatListContent.Offline -> Placeholder(
                    icon = { Icon(Icons.Outlined.CloudOff, null, Modifier.size(56.dp)) },
                    title = stringResource(R.string.chats_offline),
                    action = stringResource(R.string.chats_retry) to viewModel::refresh,
                )
                is ChatListContent.Failed -> Placeholder(
                    icon = { Icon(Icons.Filled.ErrorOutline, null, Modifier.size(56.dp)) },
                    title = content.message,
                    action = stringResource(R.string.chats_retry) to viewModel::refresh,
                )
            }
        }
    }
}

@Composable
private fun SearchBarRow(query: String, onQuery: (String) -> Unit, onClose: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surface) {
        Row(
            Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 4.dp, end = 12.dp)
                .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.statusBars),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.chats_close_search))
            }
            val focus = remember { androidx.compose.ui.focus.FocusRequester() }
            TextField(
                value = query,
                onValueChange = onQuery,
                placeholder = { Text(stringResource(R.string.chats_search)) },
                singleLine = true,
                shape = RoundedCornerShape(28.dp),
                colors = TextFieldDefaults.colors(
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
                modifier = Modifier.weight(1f).focusRequester(focus),
            )
            LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FolderTabs(state: ChatListUiState, onSelect: (String) -> Unit) {
    val selected = state.folders.indexOfFirst { it.id == state.selectedFolderId }.coerceAtLeast(0)
    PrimaryScrollableTabRow(selectedTabIndex = selected, edgePadding = 12.dp, divider = { HorizontalDivider() }) {
        state.folders.forEachIndexed { index, folder ->
            Tab(
                selected = index == selected,
                onClick = { onSelect(folder.id) },
                text = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(folder.title, maxLines = 1)
                        folder.badge?.let {
                            Spacer(Modifier.width(6.dp))
                            Badge(containerColor = MaterialTheme.colorScheme.primary) { Text(it) }
                        }
                    }
                },
            )
        }
    }
}

@Composable
private fun ChatList(state: ChatListUiState, onOpenChat: (ChatListItem) -> Unit, actions: ChatRowActions) {
    val listState = rememberLazyListState()
    LaunchedEffect(state.selectedFolderId) { listState.scrollToItem(0) }
    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
        items(state.items, key = { it.id }) { item ->
            ChatRow(item, onClick = { onOpenChat(item) }, actions = actions, modifier = Modifier.animateItem())
        }
    }
}

/** Действия меню строки чата. */
class ChatRowActions(val pin: (String) -> Unit, val read: (String) -> Unit = {}, val mute: (String) -> Unit = {})

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatRow(item: ChatListItem, onClick: () -> Unit, actions: ChatRowActions, modifier: Modifier = Modifier) {
    var menu by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(if (item.isPinned) MaterialTheme.colorScheme.surfaceContainerLow else Color.Transparent)
                .combinedClickable(onClick = onClick, onLongClick = { menu = true })
                .semantics { contentDescription = item.accessibilityLabel }
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Avatar(item.avatar, 56.dp, online = item.isOnline)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        item.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (item.isVerified) {
                        Spacer(Modifier.width(4.dp))
                        Icon(Icons.Filled.Verified, stringResource(R.string.chats_verified), Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    }
                    if (item.isMuted) {
                        Spacer(Modifier.width(4.dp))
                        Icon(Icons.AutoMirrored.Filled.VolumeOff, stringResource(R.string.chats_muted), Modifier.size(15.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Spacer(Modifier.weight(1f))
                    item.delivery?.let { DeliveryIcon(it) }
                    Spacer(Modifier.width(4.dp))
                    Text(item.time, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(3.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Preview(item, Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    Trailing(item)
                }
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(if (item.isPinned) R.string.chats_unpin else R.string.chats_pin)) },
                leadingIcon = { Icon(Icons.Filled.PushPin, null) },
                onClick = {
                    menu = false
                    actions.pin(item.id)
                },
            )
            DropdownMenuItem(
                text = { Text(if (item.isUnread) "Прочитать" else "Пометить непрочитанным") },
                leadingIcon = { Icon(if (item.isUnread) Icons.Outlined.MarkChatRead else Icons.Outlined.MarkChatUnread, null) },
                onClick = {
                    menu = false
                    actions.read(item.id)
                },
            )
            DropdownMenuItem(
                text = { Text(if (item.isMuted) "Включить уведомления" else "Выключить уведомления") },
                leadingIcon = { Icon(if (item.isMuted) Icons.Outlined.NotificationsActive else Icons.Outlined.NotificationsOff, null) },
                onClick = {
                    menu = false
                    actions.mute(item.id)
                },
            )
        }
    }
}

@Composable
private fun Preview(item: ChatListItem, modifier: Modifier) {
    val variant = MaterialTheme.colorScheme.onSurfaceVariant
    val accent = MaterialTheme.colorScheme.primary
    val error = MaterialTheme.colorScheme.error
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        item.thumbnailUrl?.let {
            AsyncImage(
                model = it,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(20.dp).clip(RoundedCornerShape(4.dp)),
            )
            Spacer(Modifier.width(6.dp))
        }
        if (item.isForwarded) {
            Icon(Icons.AutoMirrored.Filled.Forward, null, Modifier.size(15.dp), tint = variant)
            Spacer(Modifier.width(3.dp))
        }
        val draftLabel = stringResource(R.string.chats_draft)
        val text = buildAnnotatedString {
            when (item.previewStyle) {
                ChatListItem.PreviewStyle.DRAFT -> {
                    withStyle(SpanStyle(color = error)) { append(draftLabel); append(' ') }
                    append(item.preview)
                }
                ChatListItem.PreviewStyle.TYPING -> withStyle(SpanStyle(color = accent)) { append(item.preview) }
                else -> {
                    item.sender?.let { withStyle(SpanStyle(color = MaterialTheme.colorScheme.onSurface)) { append(it); append(": ") } }
                    // Подпись вложения без текста — акцентом, как в популярных мессенджерах.
                    if (item.media != null && item.preview == app.orbitle.presentation.chatlist.ChatListFormatter.mediaLabel(item.media)) {
                        withStyle(SpanStyle(color = accent)) { append(item.preview) }
                    } else {
                        append(item.preview)
                    }
                }
            }
        }
        Text(text, style = MaterialTheme.typography.bodyMedium, color = variant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Trailing(item: ChatListItem) {
    val muted = MaterialTheme.colorScheme.outline
    when {
        item.hasMention -> Box(
            Modifier.size(22.dp).clip(CircleShape).background(if (item.badgeMuted) muted else MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center,
        ) { Text("@", color = Color.White, style = MaterialTheme.typography.labelMedium) }
        item.badge is ChatBadge.Count -> Box(
            Modifier.defaultMinSize(minWidth = 22.dp, minHeight = 22.dp).clip(CircleShape)
                .background(if (item.badgeMuted) muted else MaterialTheme.colorScheme.primary)
                .padding(horizontal = 6.dp),
            contentAlignment = Alignment.Center,
        ) { Text(item.badge.text, color = Color.White, style = MaterialTheme.typography.labelMedium) }
        item.badge == ChatBadge.Dot -> Box(
            Modifier.size(12.dp).clip(CircleShape).background(if (item.badgeMuted) muted else MaterialTheme.colorScheme.primary),
        )
        item.showsPin -> Icon(Icons.Filled.PushPin, stringResource(R.string.chats_pinned), Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DeliveryIcon(state: DeliveryState) {
    val tint = if (state == DeliveryState.READ) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    val icon = when (state) {
        DeliveryState.SENDING -> Icons.Filled.Schedule
        DeliveryState.SENT -> Icons.Filled.Done
        DeliveryState.READ -> Icons.Filled.DoneAll
        DeliveryState.FAILED -> Icons.Filled.ErrorOutline
    }
    Icon(icon, null, Modifier.size(16.dp), tint = if (state == DeliveryState.FAILED) MaterialTheme.colorScheme.error else tint)
}

@Composable
fun Placeholder(icon: @Composable () -> Unit, title: String, text: String? = null, action: Pair<String, () -> Unit>? = null) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        androidx.compose.runtime.CompositionLocalProvider(
            androidx.compose.material3.LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant,
        ) { icon() }
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        text?.let {
            Spacer(Modifier.height(6.dp))
            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
        action?.let { (label, onClick) ->
            Spacer(Modifier.height(16.dp))
            Button(onClick = onClick) { Text(label) }
        }
    }
}
