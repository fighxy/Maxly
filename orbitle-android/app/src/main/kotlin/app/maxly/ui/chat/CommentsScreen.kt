package app.maxly.ui.chat

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.data.CoreErrors
import app.maxly.domain.Message
import app.maxly.domain.MessageStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import app.maxly.presentation.chat.ChatItem
import app.maxly.presentation.chat.CommentsModel
import app.maxly.presentation.chat.CommentsState
import app.maxly.presentation.chat.ReactionPalette
import app.maxly.ui.components.ChatWallpaperBackground
import app.maxly.ui.components.LocalChatBackdrop

/** Обсуждение поста канала: пост сверху, комментарии под ним, поле ввода внизу. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentsScreen(
    model: CommentsModel,
    postItem: ChatItem.Bubble,
    knownCount: Int?,
    canWrite: Boolean,
    quickReactions: List<String>,
    onClose: () -> Unit,
    /** Заблокировать автора комментария. `null` — пункта нет. Бросает ошибку сервера. */
    onBlockAuthor: (suspend (Message) -> Unit)? = null,
) {
    BackHandler(onBack = onClose)
    val state by model.state.collectAsStateWithLifecycle()
    val items = remember(state.comments) { model.items() }
    val listState = rememberLazyListState()
    val snackbar = remember { SnackbarHostState() }
    var actionsFor by remember { mutableStateOf<Message?>(null) }
    LaunchedEffect(state.error) {
        state.error?.let {
            snackbar.showSnackbar(it)
            model.consumeError()
        }
    }
    // Свой новый комментарий — прокрутка вниз к нему.
    val newest = (items.firstOrNull() as? ChatItem.Bubble)?.message
    LaunchedEffect(newest?.id) {
        if (newest != null && (newest.status == MessageStatus.SENDING || listState.firstVisibleItemIndex <= 1)) listState.animateScrollToItem(0)
    }
    val nearTop by remember { derivedStateOf { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let { it >= listState.layoutInfo.totalItemsCount - 3 } == true } }
    // Первая страница пришла: встать к самым новым, только потом подгружать старые.
    var settled by remember { mutableStateOf(false) }
    LaunchedEffect(state.phase) {
        if (state.phase == CommentsState.Phase.Loaded && !settled) {
            listState.scrollToItem(0)
            settled = true
        }
    }
    LaunchedEffect(nearTop, settled) { if (nearTop && settled) model.loadOlder() }

    Scaffold(
        topBar = {
            TopAppBar(
                navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
                title = { Text(model.title(knownCount)) },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLowest,
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().imePadding()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                ChatWallpaperBackground(LocalChatBackdrop.current)
                LazyColumn(state = listState, reverseLayout = true, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
                    items(items, key = { it.key }, contentType = { it::class }) { item ->
                        when (item) {
                            is ChatItem.Day -> DayLabel(item.label)
                            is ChatItem.Service -> DayLabel(item.text)
                            ChatItem.Unread -> UnreadDivider()
                            is ChatItem.Bubble -> BubbleRow(
                                item = item,
                                onLongPress = { actionsFor = it },
                                onReaction = { message, emoji -> model.toggleReaction(message, emoji) },
                                onReplyClick = {},
                                onRetry = { actionsFor = it },
                            )
                        }
                    }
                    item(key = "status") {
                        when (val phase = state.phase) {
                            CommentsState.Phase.Loading -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(28.dp))
                            }
                            is CommentsState.Phase.Failed -> Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(phase.text, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Spacer(Modifier.size(12.dp))
                                Button(onClick = model::reload) { Text("Повторить") }
                            }
                            CommentsState.Phase.Loaded -> when {
                                state.isLoadingOlder -> Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                                }
                                model.emptyText != null -> Text(
                                    model.emptyText!!,
                                    textAlign = TextAlign.Center,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                                )
                                else -> Spacer(Modifier.size(4.dp))
                            }
                        }
                    }
                    if (!state.hasMore || state.phase !is CommentsState.Phase.Loaded) {
                        item(key = "post") {
                            Column {
                                BubbleRow(item = postItem, onLongPress = {}, onReaction = { _, _ -> }, onReplyClick = {}, onRetry = {})
                                HorizontalDivider(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), color = MaterialTheme.colorScheme.outlineVariant)
                            }
                        }
                    }
                }
            }
            if (canWrite) {
                CommentComposer(state.draft, state.canSend, onDraft = model::setDraft, onSend = model::send)
            } else {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Text(
                        "Комментировать могут только участники",
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp),
                    )
                }
            }
        }
    }
    val blockScope = rememberCoroutineScope()
    actionsFor?.let { comment ->
        CommentActions(
            model, comment, quickReactions,
            onBlockAuthor = onBlockAuthor?.let { action ->
                { blocked ->
                    blockScope.launch {
                        try {
                            action(blocked)
                            snackbar.showSnackbar("Автор комментария заблокирован")
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Throwable) {
                            CoreErrors.map(e).userMessage?.let { snackbar.showSnackbar(it) }
                        }
                    }
                }
            },
            onDismiss = { actionsFor = null },
        )
    }
}

@Composable
private fun DayLabel(text: String) {
    Box(Modifier.fillMaxWidth().padding(vertical = 6.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(12.dp), color = Color.Black.copy(alpha = 0.25f)) {
            Text(text, color = Color.White, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(horizontal = 10.dp, vertical = 3.dp))
        }
    }
}

@Composable
private fun CommentComposer(draft: String, canSend: Boolean, onDraft: (String) -> Unit, onSend: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.navigationBarsPadding().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.Bottom) {
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                    .padding(start = 16.dp, top = 11.dp, bottom = 11.dp, end = 12.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (draft.isEmpty()) Text("Комментарий", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
                BasicTextField(
                    value = draft,
                    onValueChange = onDraft,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    maxLines = 6,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.width(6.dp))
            IconButton(
                onClick = onSend,
                enabled = canSend,
                modifier = Modifier.size(44.dp).clip(CircleShape).background(if (canSend) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    "Отправить",
                    tint = if (canSend) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

/** Меню комментария: реакции и копирование; у неотправленного — повтор и удаление. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CommentActions(
    model: CommentsModel,
    comment: Message,
    quickReactions: List<String>,
    onBlockAuthor: ((Message) -> Unit)?,
    onDismiss: () -> Unit,
) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val clipboard = LocalClipboardManager.current
    val colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        if (model.canReact(comment)) {
            val mine = comment.content.reactions.firstOrNull { it.mine }?.emoji
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                ReactionPalette.quick(quickReactions, mine).forEach { emoji ->
                    Box(
                        Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(if (emoji == mine) MaterialTheme.colorScheme.primary.copy(alpha = 0.2f) else Color.Transparent)
                            .clickable {
                                model.toggleReaction(comment, emoji)
                                onDismiss()
                            },
                        contentAlignment = Alignment.Center,
                    ) { Text(emoji, fontSize = 26.sp) }
                }
            }
        }
        if (onBlockAuthor != null && comment.authorId != "0") {
            ListItem(
                headlineContent = { Text("Заблокировать автора") },
                modifier = Modifier.clickable {
                    onBlockAuthor(comment)
                    onDismiss()
                },
                colors = colors,
            )
        }
        if (comment.status == MessageStatus.FAILED) {
            ListItem(
                headlineContent = { Text("Отправить ещё раз") },
                leadingContent = { Icon(Icons.Filled.Refresh, null) },
                colors = colors,
                modifier = Modifier.clickable { model.retry(comment.id); onDismiss() },
            )
            ListItem(
                headlineContent = { Text("Удалить", color = MaterialTheme.colorScheme.error) },
                leadingContent = { Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error) },
                colors = colors,
                modifier = Modifier.clickable { model.discard(comment.id); onDismiss() },
            )
        }
        if (comment.displayText.isNotBlank()) {
            ListItem(
                headlineContent = { Text("Копировать") },
                leadingContent = { Icon(Icons.Filled.ContentCopy, null) },
                colors = colors,
                modifier = Modifier.clickable {
                    clipboard.setText(AnnotatedString(comment.displayText))
                    onDismiss()
                },
            )
        }
        Spacer(Modifier.size(16.dp))
    }
}
