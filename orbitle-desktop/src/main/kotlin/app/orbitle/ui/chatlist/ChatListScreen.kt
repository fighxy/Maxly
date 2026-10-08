package app.orbitle.ui.chatlist

import androidx.compose.material.icons.outlined.MarkChatRead
import androidx.compose.material.icons.outlined.MarkChatUnread
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.snapshotFlow
import app.orbitle.presentation.chatlist.FolderPages
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FloatingActionButton
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
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import app.orbitle.ui.res.stringResource
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
import app.orbitle.domain.ChatSearchResult
import app.orbitle.domain.DeliveryState
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.chatlist.FoundMessageItem
import app.orbitle.presentation.chatlist.ChatBadge
import app.orbitle.presentation.chatlist.ChatListContent
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.presentation.chatlist.ChatListUiState
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.presentation.chatlist.NewChatModel
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.clickCursor
import app.orbitle.ui.components.onSecondaryClick
import app.orbitle.platform.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.zIndex
import app.orbitle.domain.ChatFolder
import app.orbitle.ui.components.DragReorder
import kotlinx.coroutines.launch
import app.orbitle.ui.components.privateBlur
import coil3.compose.AsyncImage

/** Вкладка «Чаты»: папки, поиск, закреплённые, плашка соединения. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatListScreen(
    viewModel: ChatListViewModel,
    onOpenChat: (ChatListItem) -> Unit,
    onOpenFound: (ChatSearchResult) -> Unit = {},
    onOpenMessage: (FoundMessageItem) -> Unit = {},
    privateMode: app.orbitle.domain.PrivateModePreferences = app.orbitle.domain.PrivateModePreferences(),
    onTogglePrivateMode: () -> Unit = {},
    newChat: NewChatModel? = null,
    onOpenCreated: (id: String, title: String) -> Unit = { _, _ -> },
    /** Полоса историй над поиском; `null` — без неё. */
    storiesHeader: (@Composable () -> Unit)? = null,
    /** Аватары историй у заголовка, пока полоса спрятана; `null` — историй нет. */
    storyStack: (@Composable () -> Unit)? = null,
    onAddStory: (() -> Unit)? = null,
) {
    LifecycleResumeEffect(viewModel) {
        viewModel.reloadLocal()
        onPauseOrDispose {}
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val message by viewModel.messages.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    // Папки листаются вбок, только когда полоса видна и поиск закрыт.
    val paged = state.pages.isNotEmpty()
    val folderIds = remember(state.folders) { state.folders.map { it.id } }
    val selectedPage = FolderPages.pageOf(folderIds, state.selectedFolderId)
    // Набор папок поменялся — пейджер заново встаёт на выбранную папку, номера не съезжают.
    val pagerState = remember(folderIds) { PagerState(currentPage = selectedPage) { folderIds.size } }
    val listStates = rememberSaveable(saver = FolderListStates.Saver) { FolderListStates() }
    val looseListState = rememberLazyListState()
    LaunchedEffect(folderIds) { listStates.retain(folderIds) }
    val header = rememberChatListHeaderState(snapOnIdle = true)
    val showsHeader = !state.isSearchActive && !state.isReorderingPins
    header.enabled = showsHeader
    if (paged) {
        // Вкладка выбрана нажатием — страница доезжает до неё.
        LaunchedEffect(pagerState, selectedPage) {
            if (pagerState.targetPage != selectedPage) pagerState.animateScrollToPage(selectedPage)
        }
        // Листание остановилось — выбирается папка этой страницы.
        val selectedId by rememberUpdatedState(state.selectedFolderId)
        LaunchedEffect(pagerState) {
            snapshotFlow { pagerState.settledPage }.collect { page ->
                FolderPages.selectionAfterSettle(folderIds, page, selectedId)?.let(viewModel::selectFolder)
            }
        }
    }
    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }
    BackHandler(enabled = state.isReorderingPins) { viewModel.finishPinReorder() }
    Scaffold(
        topBar = {
            Column {
                if (state.isReorderingPins) {
                    TopAppBar(
                        title = { Text("Закреплённые") },
                        actions = { TextButton(onClick = viewModel::finishPinReorder) { Text("Готово") } },
                    )
                } else if (state.isSearchActive) {
                    SearchBarRow(state.searchQuery, viewModel::setSearchQuery) { viewModel.setSearchActive(false) }
                } else {
                    TopAppBar(
                        title = {
                            // Как на iOS: пока истории спрятаны, у заголовка их стопка; нажатие их открывает.
                            Row(
                                Modifier.clip(RoundedCornerShape(12.dp))
                                    .then(if (storiesHeader != null) Modifier.clickCursor() else Modifier)
                                    .clickable(enabled = storiesHeader != null, onClick = header::toggleStories)
                                    .padding(horizontal = 4.dp, vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                androidx.compose.animation.AnimatedVisibility(storyStack != null && header.storiesHidden) {
                                    Row {
                                        storyStack?.invoke()
                                        Spacer(Modifier.width(8.dp))
                                    }
                                }
                                Text(state.banner ?: stringResource(R.string.chats_title))
                            }
                        },
                        actions = {
                            if (onAddStory != null) {
                                IconButton(onClick = onAddStory) {
                                    Icon(Icons.Outlined.AddCircleOutline, contentDescription = "Новая история")
                                }
                            }
                        },
                    )
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbar) },
        floatingActionButton = {
            // При поиске кнопок нет. Глаз — приватный режим, карандаш — новое сообщение.
            if (!state.isSearchActive && !state.isReorderingPins && (privateMode.quickToggle || newChat != null)) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.End) {
                    if (privateMode.quickToggle) {
                        androidx.compose.material3.SmallFloatingActionButton(
                            onClick = onTogglePrivateMode,
                            containerColor = if (privateMode.enabled) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
                        ) {
                            Icon(
                                if (privateMode.enabled) Icons.Filled.VisibilityOff else Icons.Outlined.Visibility,
                                if (privateMode.enabled) "Выключить приватный режим" else "Включить приватный режим",
                                tint = if (privateMode.enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (newChat != null) {
                        FloatingActionButton(onClick = newChat::show) {
                            Icon(Icons.Filled.Edit, "Новое сообщение")
                        }
                    }
                }
            }
        },
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        // Без «потянуть, чтобы обновить»: на ПК её нечем тянуть, а значок обновления висел над
        // списком. Список обновляется сам — пушами и сверкой после подключения.
        // Колесо у верхнего края возвращает поиск и истории, как потягивание на iOS.
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (showsHeader) {
                ChatListHeader(
                    header,
                    stories = storiesHeader,
                    search = { SearchCapsule(stringResource(R.string.chats_search), onClick = { viewModel.setSearchActive(true) }) },
                    folders = if (state.showsFolders) {
                        {
                            FolderCapsule(
                                state.folders,
                                selected = if (paged) pagerState.currentPage else selectedPage,
                                onSelect = viewModel::selectFolder,
                                pageOffset = if (paged) pagerState.currentPageOffsetFraction else 0f,
                            )
                        }
                    } else {
                        null
                    },
                )
            }
        Box(Modifier.weight(1f).fillMaxWidth().nestedScroll(header.connection)) {
            val open: (ChatListItem) -> Unit = {
                if (state.isSearchActive) viewModel.selectSearchResult(it.id)
                viewModel.opened(it.id)
                onOpenChat(it)
            }
            val openFound: (ChatSearchResult) -> Unit = {
                viewModel.selectSearchResult(it.id)
                onOpenFound(it)
            }
            val openMessage: (FoundMessageItem) -> Unit = {
                viewModel.selectSearchResult(it.chatId)
                onOpenMessage(it)
            }
            val actions = remember(viewModel) {
                ChatRowActions(
                    viewModel::togglePin, viewModel::toggleRead, viewModel::toggleMute, viewModel::deleteChat, viewModel::clearHistory,
                    reorderPins = viewModel::startPinReorder,
                )
            }
            if (state.isReorderingPins) {
                PinnedOrderList(state.items.filter { it.isPinned }, onReorder = viewModel::reorderPinned, onMove = viewModel::movePinned)
            } else if (paged) {
                HorizontalPager(
                    state = pagerState,
                    beyondViewportPageCount = 1,
                    key = { folderIds.getOrElse(it) { it.toString() } },
                    modifier = Modifier.fillMaxSize(),
                ) { page ->
                    val folderPage = state.pages.getOrNull(page) ?: return@HorizontalPager
                    ChatListBody(
                        folderPage.content, folderPage.items, searching = false, listState = listStates.of(folderPage.id),
                        onOpenChat = open, actions = actions, onRetry = viewModel::refresh,
                        canReorderPins = state.canReorderPins && folderPage.id == ChatFolder.ALL_ID,
                    )
                }
            } else {
                LaunchedEffect(state.selectedFolderId) { looseListState.scrollToItem(0) }
                val searching = state.isSearchActive && state.searchQuery.isNotBlank()
                val showsResults = state.content == ChatListContent.List || state.content == ChatListContent.Empty
                val hasFound = state.global.isNotEmpty() || state.messages.isNotEmpty() || state.isSearchingServer
                if (state.isSearchActive && state.searchQuery.isBlank()) {
                    RecentSearches(state.recent, looseListState, open, viewModel::removeRecent, viewModel::clearRecent, actions)
                } else if (searching && showsResults && hasFound) {
                    SearchResults(state, looseListState, open, openFound, openMessage, actions)
                } else {
                    ChatListBody(
                        state.content, state.items, searching = searching, listState = looseListState,
                        onOpenChat = open, actions = actions, onRetry = viewModel::refresh,
                        canReorderPins = state.canReorderPins,
                    )
                }
            }
        }
        }
    }
    if (newChat != null) {
        val compose by newChat.state.collectAsStateWithLifecycle()
        LaunchedEffect(compose.opened) {
            val opened = compose.opened ?: return@LaunchedEffect
            onOpenCreated(opened.id, opened.title)
            newChat.consumeOpened()
        }
        if (compose.visible) NewChatSheet(compose, newChat)
    }
}

/** Строки или пустое состояние одной папки (или результатов поиска). */
@Composable
private fun ChatListBody(
    content: ChatListContent,
    items: List<ChatListItem>,
    searching: Boolean,
    listState: LazyListState,
    onOpenChat: (ChatListItem) -> Unit,
    actions: ChatRowActions,
    onRetry: () -> Unit,
    /** В меню закреплённых строк есть «Изменить порядок». */
    canReorderPins: Boolean = false,
    /** Первая строка списка: полоса историй. */
    header: (@Composable () -> Unit)? = null,
) {
    when (content) {
        ChatListContent.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        ChatListContent.List -> ChatList(items, listState, onOpenChat, actions, canReorderPins, header)
        ChatListContent.Empty -> Placeholder(
            icon = { Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.size(56.dp)) },
            title = stringResource(if (searching) R.string.chats_search_empty else R.string.chats_empty),
            text = if (searching) null else stringResource(R.string.chats_empty_hint),
        )
        ChatListContent.Offline -> Placeholder(
            icon = { Icon(Icons.Outlined.CloudOff, null, Modifier.size(56.dp)) },
            title = stringResource(R.string.chats_offline),
            action = stringResource(R.string.chats_retry) to onRetry,
        )
        is ChatListContent.Failed -> Placeholder(
            icon = { Icon(Icons.Filled.ErrorOutline, null, Modifier.size(56.dp)) },
            title = content.message,
            action = stringResource(R.string.chats_retry) to onRetry,
        )
    }
}

/**
 * Позиции прокрутки по папкам: у каждой страницы свой [LazyListState], который переживает
 * листание, смену набора папок и поворот экрана.
 */
private class FolderListStates(private val restored: Map<String, Pair<Int, Int>> = emptyMap()) {
    private val states = HashMap<String, LazyListState>()

    fun of(folderId: String): LazyListState = states.getOrPut(folderId) {
        restored[folderId]?.let { (index, offset) -> LazyListState(index, offset) } ?: LazyListState()
    }

    /** Забывает удалённые папки. */
    fun retain(folderIds: List<String>) {
        val keep = FolderPages.retain(states, folderIds)
        states.keys.retainAll(keep.keys)
    }

    companion object {
        val Saver = listSaver<FolderListStates, Any>(
            save = { holder ->
                holder.states.flatMap { (id, s) -> listOf(id, s.firstVisibleItemIndex, s.firstVisibleItemScrollOffset) }
            },
            restore = { flat ->
                FolderListStates(flat.chunked(3).associate { (id, index, offset) -> id as String to ((index as Int) to (offset as Int)) })
            },
        )
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

@Composable
private fun ChatList(
    items: List<ChatListItem>,
    listState: LazyListState,
    onOpenChat: (ChatListItem) -> Unit,
    actions: ChatRowActions,
    canReorderPins: Boolean = false,
    header: (@Composable () -> Unit)? = null,
) {
    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
        if (header != null) item(key = "stories-strip") { header() }
        items(items, key = { it.id }) { item ->
            ChatRow(
                item,
                onClick = { onOpenChat(item) },
                actions = actions,
                modifier = Modifier.animateItem(),
                canReorderPins = canReorderPins && item.isPinned,
            )
        }
    }
}

/**
 * Режим перестановки: только закреплённые чаты с ручками. Новый порядок уходит в модель один раз,
 * когда строку отпустили; дальше строка доезжает до своего места.
 */
@Composable
private fun PinnedOrderList(items: List<ChatListItem>, onReorder: (List<String>) -> Unit, onMove: (String, Int) -> Unit) {
    val listState = rememberLazyListState()
    val drag = remember(listState) { DragReorder(listState) }
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val currentIds by rememberUpdatedState(items.map { it.id })
    val drop = {
        drag.finish()?.let(onReorder)
        scope.launch { drag.settle() }
        Unit
    }
    val byId = items.associateBy { it.id }
    // Во время перетаскивания — рабочий порядок экрана, иначе порядок модели.
    val shown = drag.order?.mapNotNull(byId::get) ?: items
    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
        items(shown, key = { it.id }) { item ->
            val index = shown.indexOf(item)
            val dragged = drag.draggedId == item.id
            PinnedOrderRow(
                original = item,
                dragged = dragged,
                canMoveUp = index > 0,
                canMoveDown = index < shown.lastIndex,
                onMove = { onMove(item.id, it) },
                dragGestures = {
                    detectDragGestures(
                        onDragStart = {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            drag.start(item.id, currentIds)
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
        item(key = "pinned-order-hint") {
            Text(
                "Потяните за ручку, чтобы поменять порядок. Он сохранится на сервере и будет таким же на других устройствах.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }
    }
}

@Composable
private fun PinnedOrderRow(
    original: ChatListItem,
    dragged: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMove: (Int) -> Unit,
    /** Жесты ручки перетаскивания. */
    dragGestures: suspend PointerInputScope.() -> Unit,
    modifier: Modifier = Modifier,
) {
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val item = if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) {
        remember(original) { app.orbitle.presentation.settings.PrivateModeMask.item(original) }
    } else {
        original
    }
    val elevation by animateDpAsState(if (dragged) 6.dp else 0.dp, label = "pinDragElevation")
    // Перекомпоновка во время перетаскивания не должна перезапускать жест.
    val gestures by rememberUpdatedState(dragGestures)
    ListItem(
        headlineContent = {
            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.privateBlur(privacy, 7.dp))
        },
        leadingContent = { Avatar(item.avatar, 44.dp, modifier = Modifier.privateBlur(privacy, 8.dp)) },
        trailingContent = {
            // Ручка: потянуть вверх или вниз. Для TalkBack — действия строки «выше» и «ниже».
            Box(Modifier.size(48.dp).pointerInput(original.id) { gestures(this) }, contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.DragHandle, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = if (dragged) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surface,
        ),
        tonalElevation = elevation,
        shadowElevation = elevation,
        modifier = modifier.semantics {
            val actions = buildList {
                if (canMoveUp) add(CustomAccessibilityAction("Переместить выше") { onMove(-1); true })
                if (canMoveDown) add(CustomAccessibilityAction("Переместить ниже") { onMove(1); true })
            }
            if (actions.isNotEmpty()) customActions = actions
        },
    )
}

/** Пустой поиск: недавние чаты, без всего списка. */
@Composable
private fun RecentSearches(
    rows: List<ChatListItem>,
    listState: LazyListState,
    onOpenChat: (ChatListItem) -> Unit,
    onRemove: (String) -> Unit,
    onClear: () -> Unit,
    actions: ChatRowActions,
) {
    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
        if (rows.isEmpty()) return@LazyColumn
        item(key = "recent-header") {
            Row(
                Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.chats_search_recent),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onClear) { Text(stringResource(R.string.chats_search_clear)) }
            }
        }
        items(rows, key = { "recent-${it.id}" }) { item ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                ChatRow(item, onClick = { onOpenChat(item) }, actions = actions, modifier = Modifier.weight(1f))
                IconButton(onClick = { onRemove(item.id) }) {
                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.chats_search_remove_recent))
                }
            }
        }
    }
}

/** Результаты поиска: свои чаты, затем найденное на сервере. */
@Composable
private fun SearchResults(
    state: ChatListUiState,
    listState: LazyListState,
    onOpenChat: (ChatListItem) -> Unit,
    onOpenFound: (ChatSearchResult) -> Unit,
    onOpenMessage: (FoundMessageItem) -> Unit,
    actions: ChatRowActions,
) {
    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
        items(state.items, key = { it.id }) { item ->
            ChatRow(item, onClick = { onOpenChat(item) }, actions = actions, modifier = Modifier.animateItem())
        }
        if (state.global.isNotEmpty() || (state.isSearchingServer && state.messages.isEmpty())) {
            item(key = "global-header") { SectionHeader(stringResource(R.string.chats_search_global)) }
        }
        items(state.global, key = { "global-${it.id}" }) { found ->
            FoundChatRow(found, onClick = { onOpenFound(found) })
        }
        if (state.messages.isNotEmpty()) {
            item(key = "messages-header") { SectionHeader(stringResource(R.string.chats_search_messages)) }
        }
        items(state.messages, key = { "message-${it.chatId}-${it.messageId}" }) { found ->
            FoundMessageRow(found, onClick = { onOpenMessage(found) })
        }
        if (state.isSearchingServer) {
            item(key = "global-progress") {
                Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

/** Найденное сообщение: чат, время, автор и текст; в приватном режиме — как строка чата. */
@Composable
private fun FoundMessageRow(found: FoundMessageItem, onClick: () -> Unit) {
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val masked = privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER
    val mask = app.orbitle.presentation.settings.PrivateModeMask
    val title = if (masked) mask.chatTitle(found.chatType, found.isSavedMessages) else found.chatTitle
    val text = if (masked) mask.HIDDEN_TEXT else found.author?.let { "$it: ${found.snippet}" } ?: found.snippet
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).privateBlur(privacy, 7.dp),
                )
                if (found.time.isNotEmpty()) {
                    Spacer(Modifier.width(8.dp))
                    Text(found.time, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
            }
            Spacer(Modifier.height(2.dp))
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.privateBlur(privacy, 7.dp),
            )
        }
    }
}

/** Публичный чат или канал с сервера; в приватном режиме — без имени и фото, как строка чата. */
@Composable
private fun FoundChatRow(found: ChatSearchResult, onClick: () -> Unit) {
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val masked = privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER
    val title = if (masked) app.orbitle.presentation.settings.PrivateModeMask.chatTitle(found.type) else found.title
    val subtitle = if (masked) null else found.subtitle
    val avatar = remember(found, masked) {
        val color = ChatAvatar.colorIndex(found.id)
        val initials = ChatAvatar.initials(found.title)
        val url = found.avatarUrl
        when {
            masked -> ChatAvatar(ChatAvatar.Kind.Initials(""), color)
            url != null -> ChatAvatar(ChatAvatar.Kind.Photo(url, initials), color)
            else -> ChatAvatar(ChatAvatar.Kind.Initials(initials), color)
        }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Avatar(avatar, 48.dp, modifier = Modifier.privateBlur(privacy, 8.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.privateBlur(privacy, 7.dp),
            )
            subtitle?.let {
                Spacer(Modifier.height(2.dp))
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.privateBlur(privacy, 7.dp),
                )
            }
        }
    }
}

/** Действия меню строки чата. */
class ChatRowActions(
    val pin: (String) -> Unit,
    val read: (String) -> Unit = {},
    val mute: (String) -> Unit = {},
    val deleteChat: (String, Boolean) -> Unit = { _, _ -> },
    val clearHistory: (String, Boolean) -> Unit = { _, _ -> },
    /** Открыть режим перестановки закреплённых. */
    val reorderPins: () -> Unit = {},
)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ChatRow(
    original: ChatListItem,
    onClick: () -> Unit,
    actions: ChatRowActions,
    modifier: Modifier = Modifier,
    /** В меню есть «Изменить порядок»: строка закреплена, а список — папка «Все» без поиска. */
    canReorderPins: Boolean = false,
) {
    var menu by remember { mutableStateOf(false) }
    var erase by remember { mutableStateOf<app.orbitle.ui.chat.ChatErase?>(null) }
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val item = if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) {
        remember(original) { app.orbitle.presentation.settings.PrivateModeMask.item(original) }
    } else if (privacy == app.orbitle.domain.PrivateModeDisplay.BLUR) {
        original.copy(isOnline = false)
    } else {
        original
    }
    Box(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(if (item.isPinned) MaterialTheme.colorScheme.surfaceContainerLow else Color.Transparent)
                .onSecondaryClick { menu = true }
                .combinedClickable(onClick = onClick, onLongClick = { menu = true })
                .semantics { contentDescription = item.accessibilityLabel }
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Кольцо историй собеседника: касание аватара открывает его истории. Заглушки
            // приватного режима колец не показывают.
            val stories = app.orbitle.ui.stories.LocalStoryRings.current
            val ownerType = when (item.type) {
                app.orbitle.domain.ChatType.GROUP -> app.orbitle.domain.StoryOwner.Type.CHAT
                app.orbitle.domain.ChatType.CHANNEL -> app.orbitle.domain.StoryOwner.Type.CHANNEL
                else -> app.orbitle.domain.StoryOwner.Type.USER
            }
            val ownerId = if (item.type == app.orbitle.domain.ChatType.PRIVATE) item.peerId else item.id
            val ring = if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) null else stories.ringFor(ownerId, ownerType)
            app.orbitle.ui.stories.StoryRingAvatar(
                item.avatar, ring, 56.dp, online = item.isOnline, modifier = Modifier.privateBlur(privacy, 8.dp),
                onRingClick = ownerId?.let { owner -> { stories.open(owner) } },
            )
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // Название с отметками занимает всё свободное место, время прижато к правому краю.
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            item.title,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false).privateBlur(privacy, 7.dp),
                        )
                        if (item.isVerified) {
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.Filled.Verified, stringResource(R.string.chats_verified), Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                        }
                        if (item.isMuted) {
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.AutoMirrored.Filled.VolumeOff, stringResource(R.string.chats_muted), Modifier.size(15.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Spacer(Modifier.width(8.dp))
                    item.delivery?.let {
                        DeliveryIcon(it)
                        Spacer(Modifier.width(4.dp))
                    }
                    Text(item.time, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
                Spacer(Modifier.height(3.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Preview(item, Modifier.weight(1f).privateBlur(privacy, 7.dp))
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
            if (canReorderPins) {
                DropdownMenuItem(
                    text = { Text("Изменить порядок") },
                    leadingIcon = { Icon(Icons.Filled.SwapVert, null) },
                    onClick = {
                        menu = false
                        actions.reorderPins()
                    },
                )
            }
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
            DropdownMenuItem(
                text = { Text("Очистить историю") },
                onClick = {
                    menu = false
                    erase = app.orbitle.ui.chat.ChatErase.CLEAR
                },
            )
            DropdownMenuItem(
                text = { Text("Удалить чат") },
                onClick = {
                    menu = false
                    erase = app.orbitle.ui.chat.ChatErase.DELETE
                },
            )
        }
        erase?.let { kind ->
            val hidden = privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE
            app.orbitle.ui.chat.EraseChatDialog(
                kind = kind,
                type = original.type,
                saved = original.id == app.orbitle.domain.Chat.SAVED_MESSAGES_ID,
                title = if (hidden) "этот чат" else original.title,
                onChoose = { forEveryone ->
                    erase = null
                    if (kind == app.orbitle.ui.chat.ChatErase.DELETE) actions.deleteChat(original.id, forEveryone)
                    else actions.clearHistory(original.id, forEveryone)
                },
                onDismiss = { erase = null },
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
                    val media = item.media
                    if (media != null && item.preview == app.orbitle.presentation.chatlist.ChatListFormatter.mediaLabel(media)) {
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
    val badge = item.badge
    when {
        item.hasMention -> Box(
            Modifier.size(22.dp).clip(CircleShape).background(if (item.badgeMuted) muted else MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center,
        ) { Text("@", color = if (item.badgeMuted) Color.White else MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelMedium) }
        badge is ChatBadge.Count -> Box(
            Modifier.defaultMinSize(minWidth = 22.dp, minHeight = 22.dp).clip(CircleShape)
                .background(if (item.badgeMuted) muted else MaterialTheme.colorScheme.primary)
                .padding(horizontal = 6.dp),
            contentAlignment = Alignment.Center,
        ) { Text(badge.text, color = if (item.badgeMuted) Color.White else MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelMedium) }
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
