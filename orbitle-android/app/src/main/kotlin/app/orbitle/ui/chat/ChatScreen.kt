package app.orbitle.ui.chat

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
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
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import app.orbitle.presentation.chat.ChatItem
import app.orbitle.presentation.chat.ChatUiState
import app.orbitle.presentation.chat.ChatViewModel
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.ChatWallpaperBackground
import app.orbitle.ui.components.LocalChatBackdrop
import app.orbitle.ui.theme.OrbitleAccent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Экран переписки. Лента перевёрнута: новые сообщения внизу, история догружается вверх. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(model: ChatViewModel, onBack: () -> Unit, onOpenProfile: () -> Unit = {}, mediaUserAgent: String = "") {
    val state by model.state.collectAsStateWithLifecycle()
    val mediaState = model.media.state.collectAsStateWithLifecycle()
    val playback = model.media.playback.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val bubbleMedia = remember(model) {
        BubbleMedia(
            playback = playback,
            media = mediaState,
            canPlay = model.media::canPlay,
            canTranscribe = model.media::canTranscribe,
            onVoice = model.media::toggleVoice,
            onSeek = model.media::seekVoice,
            onTranscript = model.media::toggleTranscript,
            onVisual = model.media::openVisual,
            onFile = model.media::openFile,
        )
    }
    val openFile = mediaState.value.openFile
    LaunchedEffect(openFile) {
        val file = openFile ?: return@LaunchedEffect
        model.media.consumeOpenFile()
        if (!FileOpener.open(context, file)) model.notify("Нет приложения, чтобы открыть этот файл")
    }
    val notice by model.messages.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var actionsFor by remember { mutableStateOf<Message?>(null) }
    var deleting by remember { mutableStateOf<Message?>(null) }
    var highlighted by remember { mutableStateOf<String?>(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            model.setActive(true)
            try {
                kotlinx.coroutines.awaitCancellation()
            } finally {
                model.setActive(false)
            }
        }
    }
    LaunchedEffect(notice) {
        val text = notice ?: return@LaunchedEffect
        snackbar.showSnackbar(text)
        model.consumeMessage()
    }
    // Ближе к верху ленты — следующая страница истории.
    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index to listState.layoutInfo.totalItemsCount }
            .collect { (last, total) -> if (last != null && total > 0 && last >= total - 6) model.loadOlder() }
    }
    // Своё новое сообщение или новое внизу, когда лента у низа: прокрутить к нему.
    val newest = state.items.firstOrNull()?.key
    LaunchedEffect(newest) {
        val first = state.items.firstOrNull() as? ChatItem.Bubble
        if (first != null && (first.outgoing && first.message.status == MessageStatus.SENDING || listState.firstVisibleItemIndex <= 1)) {
            listState.animateScrollToItem(0)
        }
    }
    val awayFromBottom by remember { derivedStateOf { listState.firstVisibleItemIndex > 2 } }

    CompositionLocalProvider(LocalBubbleMedia provides bubbleMedia) {
    Scaffold(
        topBar = { ChatTopBar(state, onBack, onOpenProfile) },
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLowest,
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().imePadding()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                ChatWallpaperBackground(LocalChatBackdrop.current)
                when {
                    state.isLoading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                    state.emptyHint != null -> EmptyHint(state.emptyHint!!, Modifier.align(Alignment.Center))
                }
                LazyColumn(
                    state = listState,
                    reverseLayout = true,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(vertical = 8.dp),
                ) {
                    items(state.items, key = { it.key }, contentType = { it::class }) { item ->
                        when (item) {
                            is ChatItem.Day -> DayChip(item.label)
                            is ChatItem.Service -> ServiceChip(item.text)
                            is ChatItem.Bubble -> BubbleRow(
                                item = item,
                                onLongPress = { actionsFor = it },
                                onReaction = { message, emoji -> model.toggleReaction(message, emoji) },
                                onReplyClick = { id ->
                                    val index = state.items.indexOfFirst { it.key == id }
                                    if (index >= 0) scope.launch {
                                        listState.animateScrollToItem(index)
                                        highlighted = id
                                        delay(1_200)
                                        highlighted = null
                                    }
                                },
                                onRetry = { actionsFor = it },
                                highlighted = highlighted == item.key,
                            )
                        }
                    }
                    if (state.isLoadingOlder) {
                        item(key = "older") {
                            Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                            }
                        }
                    }
                }
                androidx.compose.animation.AnimatedVisibility(
                    visible = awayFromBottom,
                    enter = fadeIn() + scaleIn(),
                    exit = fadeOut() + scaleOut(),
                    modifier = Modifier.align(Alignment.BottomEnd).padding(12.dp),
                ) {
                    SmallFloatingActionButton(
                        onClick = { scope.launch { listState.animateScrollToItem(0) } },
                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    ) { Icon(Icons.Filled.KeyboardArrowDown, "Вниз") }
                }
            }
            if (state.canWrite) {
                Composer(
                    state = state,
                    onDraft = model::setDraft,
                    onSend = model::send,
                    onCancelReply = model::cancelReply,
                    onCancelEdit = model::cancelEdit,
                )
            } else {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Text(
                        "Писать в этот чат нельзя",
                        Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp),
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    }

    mediaState.value.viewer?.let { viewer ->
        MediaViewer(viewer, mediaUserAgent, onPage = model.media::showPage, onClose = model.media::closeViewer)
    }
    actionsFor?.let { message ->
        MessageActions(
            model = model,
            message = message,
            onDismiss = { actionsFor = null },
            onDelete = { deleting = message },
        )
    }
    deleting?.let { message ->
        DeleteDialog(model, message, onDismiss = { deleting = null })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatTopBar(state: ChatUiState, onBack: () -> Unit, onOpenProfile: () -> Unit) {
    TopAppBar(
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
        title = {
            val header = state.header ?: return@TopAppBar
            Row(Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onOpenProfile), verticalAlignment = Alignment.CenterVertically) {
                Avatar(header.avatar, 40.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(header.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        if (header.isVerified) {
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.Filled.Verified, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                        }
                    }
                    Text(
                        header.subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (header.subtitleAccent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        },
    )
}

@Composable
private fun DayChip(label: String) {
    Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.9f)) {
            Text(label, Modifier.padding(horizontal = 10.dp, vertical = 3.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ServiceChip(text: String) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 4.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.8f)) {
            Text(text, Modifier.padding(horizontal = 10.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun EmptyHint(text: String, modifier: Modifier) {
    Surface(modifier.padding(32.dp), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Text(text, Modifier.padding(20.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Поле ввода с плашкой ответа или правки. */
@Composable
private fun Composer(
    state: ChatUiState,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
    onCancelReply: () -> Unit,
    onCancelEdit: () -> Unit,
) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.navigationBarsPadding()) {
            val editing = state.editing
            val reply = state.replyTo
            if (editing != null || reply != null) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (editing != null) Icons.Filled.Edit else Icons.AutoMirrored.Filled.Reply, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            if (editing != null) "Редактирование" else reply!!.authorName.ifEmpty { "Ответ" },
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.labelLarge,
                            maxLines = 1,
                        )
                        Text((editing ?: reply)!!.replySnippet, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(onClick = if (editing != null) onCancelEdit else onCancelReply) { Icon(Icons.Filled.Close, "Отменить") }
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.Bottom) {
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 44.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                        .padding(horizontal = 16.dp, vertical = 11.dp),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    if (state.draft.isEmpty()) Text("Сообщение", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
                    // Текст правки или восстановленный черновик приходит извне: курсор в конец.
                    var field by remember { mutableStateOf(TextFieldValue(state.draft, TextRange(state.draft.length))) }
                    if (field.text != state.draft) field = TextFieldValue(state.draft, TextRange(state.draft.length))
                    val focus = remember { FocusRequester() }
                    LaunchedEffect(editing?.id, reply?.id) { if (editing != null || reply != null) runCatching { focus.requestFocus() } }
                    BasicTextField(
                        value = field,
                        onValueChange = {
                            field = it
                            if (it.text != state.draft) onDraft(it.text)
                        },
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp),
                        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                        maxLines = 6,
                        modifier = Modifier.fillMaxWidth().focusRequester(focus),
                    )
                }
                Spacer(Modifier.width(6.dp))
                val enabled = state.canSend
                Box(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(if (enabled) OrbitleAccent else MaterialTheme.colorScheme.surfaceContainerHighest)
                        .clickable(enabled = enabled, onClick = onSend),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (state.editing != null) Icons.Filled.Check else Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Отправить",
                        tint = if (enabled) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** Меню сообщения: быстрые реакции и действия. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MessageActions(model: ChatViewModel, message: Message, onDismiss: () -> Unit, onDelete: () -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val clipboard = LocalClipboardManager.current
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        if (model.canReact(message)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                val mine = message.content.reactions.firstOrNull { it.mine }?.emoji
                model.quickReactions(message).forEach { emoji ->
                    Box(
                        Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(if (emoji == mine) MaterialTheme.colorScheme.primary.copy(alpha = 0.2f) else Color.Transparent)
                            .clickable {
                                model.toggleReaction(message, emoji)
                                onDismiss()
                            },
                        contentAlignment = Alignment.Center,
                    ) { Text(emoji, fontSize = 26.sp) }
                }
            }
        }
        val colors = ListItemDefaults.colors(containerColor = Color.Transparent)
        if (message.status == MessageStatus.FAILED) {
            ListItem(
                headlineContent = { Text("Отправить ещё раз") },
                leadingContent = { Icon(Icons.Filled.Refresh, null) },
                colors = colors,
                modifier = Modifier.clickable { model.retry(message); onDismiss() },
            )
        }
        if (message.status == MessageStatus.SENT && message.id.toLongOrNull() != null) {
            ListItem(
                headlineContent = { Text("Ответить") },
                leadingContent = { Icon(Icons.AutoMirrored.Filled.Reply, null) },
                colors = colors,
                modifier = Modifier.clickable { model.beginReply(message); onDismiss() },
            )
        }
        if (message.displayText.isNotBlank()) {
            ListItem(
                headlineContent = { Text("Копировать") },
                leadingContent = { Icon(Icons.Filled.ContentCopy, null) },
                colors = colors,
                modifier = Modifier.clickable {
                    clipboard.setText(AnnotatedString(message.displayText))
                    onDismiss()
                },
            )
        }
        if (model.canEdit(message)) {
            ListItem(
                headlineContent = { Text("Изменить") },
                leadingContent = { Icon(Icons.Filled.Edit, null) },
                colors = colors,
                modifier = Modifier.clickable { model.beginEdit(message); onDismiss() },
            )
        }
        ListItem(
            headlineContent = { Text("Удалить", color = MaterialTheme.colorScheme.error) },
            leadingContent = { Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error) },
            colors = colors,
            modifier = Modifier.clickable { onDismiss(); onDelete() },
        )
        Spacer(Modifier.size(16.dp))
    }
}

@Composable
private fun DeleteDialog(model: ChatViewModel, message: Message, onDismiss: () -> Unit) {
    val everyone = model.canDeleteForEveryone(message)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Удалить сообщение?") },
        text = {
            Text(
                when {
                    model.deletesWithoutChoice -> "Сообщение удалится из «Избранного» на всех устройствах."
                    everyone -> "Можно удалить только у себя или у всех участников чата."
                    else -> "Сообщение удалится только у вас."
                },
            )
        },
        confirmButton = {
            Row {
                if (everyone) {
                    TextButton(onClick = { model.delete(message, forEveryone = false); onDismiss() }) { Text("У себя") }
                    TextButton(onClick = { model.delete(message, forEveryone = true); onDismiss() }) {
                        Text("У всех", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.SemiBold)
                    }
                } else {
                    TextButton(onClick = { model.delete(message, forEveryone = false); onDismiss() }) {
                        Text("Удалить", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}
