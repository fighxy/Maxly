package app.orbitle.ui.chat

import androidx.compose.material3.Button
import app.orbitle.presentation.chat.BotAppRequest
import app.orbitle.domain.InlineButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import app.orbitle.presentation.chat.SaveTarget
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Download
import app.orbitle.presentation.chat.ReactionPalette
import androidx.compose.material.icons.outlined.Group
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.Sticker
import app.orbitle.presentation.stickers.StickerPanel
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.ui.layout.ContentScale
import app.orbitle.domain.OutgoingFile
import coil3.compose.AsyncImage
import java.io.File
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
import androidx.compose.material.icons.outlined.MarkChatUnread
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.filled.Mic
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import app.orbitle.ui.components.privateBlur
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Forward
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Poll
import androidx.compose.material.icons.outlined.Schedule
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
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.ChatWallpaperBackground
import app.orbitle.ui.components.edgeFade
import app.orbitle.ui.components.LocalChatBackdrop
import app.orbitle.ui.theme.OrbitleAccent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Экран переписки. Лента перевёрнута: новые сообщения внизу, история догружается вверх. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    model: ChatViewModel,
    onBack: () -> Unit,
    onOpenProfile: () -> Unit = {},
    mediaUserAgent: String = "",
    /** Куда можно переслать сообщение. */
    forwardTargets: () -> List<ChatListItem> = { emptyList() },
    /** Капсула «Отключить приватный режим» над лентой. */
    onDisablePrivateMode: () -> Unit = {},
    /** Эмодзи двойного нажатия. `null` — сервер выключил быструю реакцию. */
    quickReaction: String? = null,
    /** Действие, выбранное в профиле этого чата: экран открывает его, когда профиль закрылся. */
    requestedAction: ChatAction? = null,
    onActionHandled: () -> Unit = {},
    /** Мини-приложение бота поверх чата: кнопка «Открыть приложение» и inline-кнопки `OPEN_APP`. */
    botApp: @Composable (request: BotAppRequest, onClose: () -> Unit) -> Unit = { _, onClose -> onClose() },
) {
    val state by model.state.collectAsStateWithLifecycle()
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    // Открытые касанием пузыри приватного режима: закрываются через 15 секунд,
    // при уходе из чата, сворачивании и смене вида.
    val revealed = remember { androidx.compose.runtime.mutableStateListOf<String>() }
    val revealScope = rememberCoroutineScope()
    val revealJobs = remember { mutableMapOf<String, kotlinx.coroutines.Job>() }
    val hideAll = {
        revealJobs.values.forEach { it.cancel() }
        revealJobs.clear()
        revealed.clear()
    }
    val reveal: (String) -> Unit = { id ->
        revealJobs.remove(id)?.cancel()
        if (id !in revealed) revealed.add(id)
        revealJobs[id] = revealScope.launch {
            delay(app.orbitle.presentation.settings.PrivateModeMask.REVEAL_MILLIS)
            revealed.remove(id)
            revealJobs.remove(id)
        }
    }
    LaunchedEffect(privacy) { hideAll() }
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
            onRoundEnded = model.media::stopRound,
            userAgent = mediaUserAgent,
        )
    }
    var attaching by remember { mutableStateOf(false) }
    var editingPhoto by remember(model) { mutableStateOf<OutgoingFile?>(null) }
    val photoSessions = remember(model) { mutableMapOf<String,app.orbitle.ui.photo.PhotoEditorSession>() }
    val recorderScope = rememberCoroutineScope()
    val voiceRecorder = remember { app.orbitle.media.AndroidVoiceRecorder(context.applicationContext, recorderScope) }
    val importScope = rememberCoroutineScope()
    val importUris: (List<Uri>) -> Unit = { uris ->
        if (uris.isNotEmpty()) importScope.launch { model.addAttachments(AttachmentImporter.import(context, uris.take(OutgoingFile.LIMIT))) }
    }
    val pickVisual = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(OutgoingFile.LIMIT), importUris)
    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments(), importUris)
    // До Android 10 запись в общие папки требует разрешения.
    var pendingSave by remember { mutableStateOf<Pair<Message, SaveTarget>?>(null) }
    val storagePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pendingSave?.let { (message, target) -> if (granted) model.media.save(message, target) else model.notify("Нет доступа к памяти телефона") }
        pendingSave = null
    }
    val requestViewerSave: () -> Unit = {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q ||
            androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
        ) model.media.saveViewed() else storagePermission.launch(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
    }
    val requestSave: (Message, SaveTarget) -> Unit = { message, target ->
        val allowed = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q ||
            androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (allowed) {
            model.media.save(message, target)
        } else {
            pendingSave = message to target
            storagePermission.launch(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
    }
    val openFile = mediaState.value.openFile
    LaunchedEffect(openFile) {
        val file = openFile ?: return@LaunchedEffect
        model.media.consumeOpenFile()
        if (!FileOpener.open(context, file)) model.notify("Нет приложения, чтобы открыть этот файл")
    }
    val notice by model.messages.collectAsStateWithLifecycle()
    val openUrl by model.openUrl.collectAsStateWithLifecycle()
    val botAppRequest by model.botApp.collectAsStateWithLifecycle()
    val uriHandler = LocalUriHandler.current
    val buttonClipboard = LocalClipboardManager.current
    LaunchedEffect(openUrl) {
        val url = openUrl ?: return@LaunchedEffect
        model.consumeOpenUrl()
        if (runCatching { uriHandler.openUri(url) }.isFailure) model.notify("Не удалось открыть ссылку")
    }
    val pressButton: (Message, InlineButton) -> Unit = { message, button ->
        when (val action = button.action) {
            is InlineButton.Action.Copy -> {
                buttonClipboard.setText(AnnotatedString(action.text))
                model.notify("Скопировано")
            }
            else -> model.pressButton(message, button)
        }
    }
    val snackbar = remember { SnackbarHostState() }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var actionsFor by remember { mutableStateOf<Message?>(null) }
    var deleting by remember { mutableStateOf<Message?>(null) }
    var forwarding by remember { mutableStateOf<Message?>(null) }
    var reactionUsers by remember { mutableStateOf<app.orbitle.presentation.chat.ReactionUsersModel?>(null) }
    var highlighted by remember { mutableStateOf<String?>(null) }
    var searching by remember { mutableStateOf(false) }
    var toolsOpen by remember { mutableStateOf(false) }
    var eraseChat by remember { mutableStateOf<ChatErase?>(null) }
    var makingPoll by remember { mutableStateOf(false) }
    var scheduling by remember { mutableStateOf(false) }
    var confirmingCall by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }
    val scrollToMessage: (String) -> Unit = { id ->
        val index = state.items.indexOfFirst { it.key == id }
        if (index >= 0) scope.launch {
            listState.animateScrollToItem(index)
            highlighted = id
            delay(1_200)
            highlighted = null
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            model.setActive(true)
            try {
                kotlinx.coroutines.awaitCancellation()
            } finally {
                model.setActive(false)
                hideAll()
            }
        }
    }
    LaunchedEffect(notice) {
        val text = notice ?: return@LaunchedEffect
        snackbar.showSnackbar(text)
        model.consumeMessage()
    }
    LaunchedEffect(requestedAction) {
        val action = requestedAction ?: return@LaunchedEffect
        // Сначала уезжает профиль, потом открывается лист. Запрос снимается после: смена ключа
        // отменила бы эту задачу посреди паузы.
        delay(300)
        when (action) {
            ChatAction.SEARCH -> searching = true
            ChatAction.TOOLS -> {
                toolsOpen = true
                model.loadTools()
            }
            ChatAction.CALL -> confirmingCall = true
            ChatAction.CLEAR_HISTORY -> eraseChat = ChatErase.CLEAR
            ChatAction.DELETE_CHAT -> eraseChat = ChatErase.DELETE
            ChatAction.LEAVE -> leaving = true
        }
        onActionHandled()
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
    // Чат с непрочитанными открывается на разделителе: он у верха, ниже — новые сообщения.
    val density = LocalDensity.current
    var unreadShown by remember(model) { mutableStateOf(false) }
    val unreadIndex = state.items.indexOfFirst { it is ChatItem.Unread }
    LaunchedEffect(unreadIndex) {
        if (unreadIndex < 0 || unreadShown) return@LaunchedEffect
        unreadShown = true
        listState.scrollToItem(unreadIndex)
        val viewport = listState.layoutInfo.viewportSize.height
        val gap = with(density) { 96.dp.toPx() }
        if (viewport > gap) listState.scrollBy(-(viewport - gap))
    }
    val awayFromBottom by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            app.orbitle.presentation.chat.ScrollDown.isVisible(info.visibleItemsInfo.map { it.index }, info.totalItemsCount)
        }
    }

    CompositionLocalProvider(LocalBubbleMedia provides bubbleMedia) { Box(Modifier.fillMaxSize()) {
    // Обои на весь экран: не прокручиваются с лентой и не двигаются за клавиатурой.
    ChatWallpaperBackground(LocalChatBackdrop.current)
    Scaffold(
        topBar = {
            // Поиск и «Ещё» переехали в профиль чата: справа в шапке кнопок нет.
            ChatTopBar(state, onBack, onOpenProfile, privacy)
        },
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0),
        containerColor = Color.Transparent,
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().imePadding()) {
            state.pinnedText?.let { pinned ->
                PinBanner(pinned, onOpen = { state.pinnedMessageId?.let(scrollToMessage) }, onUnpin = model::unpin)
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.isLoading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                    state.emptyHint != null -> EmptyHint(state.emptyHint!!, Modifier.align(Alignment.Center))
                }
                LazyColumn(
                    state = listState,
                    reverseLayout = true,
                    // Тонкое растворение сверху, лёгкое снизу — в обои или фон.
                    modifier = Modifier.fillMaxSize().edgeFade(top = 10.dp, bottom = 16.dp),
                    contentPadding = PaddingValues(top = if (privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE) 88.dp else 10.dp, bottom = 12.dp),
                ) {
                    items(state.items, key = { it.key }, contentType = { it::class }) { item ->
                        when (item) {
                            is ChatItem.Day -> DayChip(item.label)
                            is ChatItem.Service -> ServiceChip(item.text)
                            ChatItem.Unread -> UnreadDivider()
                            is ChatItem.Bubble -> if (privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE && item.key !in revealed) {
                                PrivateBubble(item, privacy) { reveal(item.key) }
                            } else BubbleRow(
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
                                onSwipeReply = if (state.canWrite) model::beginReply else null,
                                onComments = model::openComments,
                                onVote = model::vote,
                                onDoubleTap = { message -> quickReaction?.let { model.toggleReaction(message, it) } },
                                onButton = pressButton,
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
                    visible = privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE,
                    enter = fadeIn(),
                    exit = fadeOut(),
                    modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
                ) {
                    PrivateModeCapsule(showsHint = state.items.any { it is ChatItem.Bubble }, onDisable = onDisablePrivateMode)
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
            if (state.botAppId != null) {
                FilledTonalButton(
                    onClick = model::openBotApp,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                ) { Text("Открыть приложение") }
            }
            if (state.canWrite) {
                Composer(
                    state = state,
                    onDraft = model::setDraft,
                    onSend = model::send,
                    onCancelReply = model::cancelReply,
                    onCancelEdit = model::cancelEdit,
                    onAttach = { attaching = true },
                    onRemoveAttachment = model::removeAttachment,
                    onEditPhoto = { editingPhoto = it },
                    panel = model.stickers,
                    onSticker = model::sendSticker,
                    onAnimoji = model::noteAnimoji,
                    onCancelUpload = { model.cancelUpload() },
                    recorder = voiceRecorder,
                    onVoice = model::sendVoice,
                    onRecordingStart = model.media::stopVoice,
                    onMention = model::insertMention,
                    onCommand = model::insertCommand,
                )
            } else if (state.join != null) {
                val join = state.join!!
                // Канал или группа вне списка (из поиска): вступление вместо плашки.
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Button(
                        onClick = model::join,
                        enabled = !join.busy,
                        modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp),
                    ) {
                        if (join.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(join.label)
                    }
                }
            } else {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Text(
                        if (state.header?.type == app.orbitle.domain.ChatType.CHANNEL) "Писать в канал могут только администраторы" else "Писать в этот чат нельзя",
                        Modifier.fillMaxWidth().navigationBarsPadding().padding(16.dp),
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

        val openedComments by model.commentsModel.collectAsStateWithLifecycle()
        openedComments?.let { comments ->
            val postItem = remember(comments, state.items) {
                (state.items.firstOrNull { it.key == comments.post.id } as? ChatItem.Bubble)?.copy(comments = null)
                    ?: ChatItem.Bubble(comments.post, false, "", null, 0, false, null, false, false)
            }
            CommentsScreen(
                model = comments,
                postItem = postItem,
                knownCount = model.commentCount(comments.post),
                canWrite = true,
                quickReactions = state.reactionCatalog,
                onClose = model::closeComments,
            )
        }
        botAppRequest?.let { request ->
            BackHandler { model.consumeBotApp() }
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
                botApp(request, model::consumeBotApp)
            }
        }
    } }

    editingPhoto?.let { original ->
        app.orbitle.ui.photo.PhotoEditor(
            file = original,
            load = app.orbitle.media.AndroidPhotoEditor::load,
            onClose = { editingPhoto = null },
            session = photoSessions[original.path],
            onSave = { edited, session -> photoSessions.remove(original.path);photoSessions[edited.path]=session;model.replaceAttachment(original, edited); editingPhoto = null },
        )
    }

    if (attaching) {
        AttachSheet(
            onDismiss = { attaching = false },
            onMedia = {
                attaching = false
                pickVisual.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
            },
            onFile = {
                attaching = false
                pickFiles.launch(arrayOf("*/*"))
            },
            onPoll = {
                attaching = false
                makingPoll = true
            },
            onSchedule = {
                attaching = false
                scheduling = true
            },
        )
    }
    mediaState.value.viewer?.let { viewer ->
        MediaViewer(
            viewer, mediaUserAgent, onPage = model.media::showPage, onClose = model.media::closeViewer,
            onSave = if (model.media.canSave(Message(viewer.messageId, model.chatId, "", "", viewer.timeMs, content = app.orbitle.domain.MessageContent(attachments = viewer.items)), SaveTarget.GALLERY)) {
                { requestViewerSave() }
            } else null,
            saving = viewer.messageId in mediaState.value.saving,
        )
    }
    actionsFor?.let { message ->
        MessageActions(
            model = model,
            message = message,
            onDismiss = { actionsFor = null },
            onDelete = { deleting = message },
            onForward = { forwarding = message },
            onReactionUsers = { reactionUsers = model.reactionUsers(message) },
            onSave = { target -> requestSave(message, target) },
            onMarkUnread = { model.markUnread(message, onBack) },
        )
    }
    reactionUsers?.let { users ->
        ReactionUsersSheet(users, onDismiss = { reactionUsers = null })
    }
    forwarding?.let { message ->
        val targets = remember(message) { forwardTargets() }
        ForwardPicker(
            targets = targets,
            onPick = { target ->
                forwarding = null
                model.forward(message, target)
            },
            onDismiss = { forwarding = null },
        )
    }
    deleting?.let { message ->
        DeleteDialog(model, message, onDismiss = { deleting = null })
    }
    if (searching) {
        InChatSearchSheet(
            model,
            onHit = { id ->
                searching = false
                scrollToMessage(id)
            },
            onDismiss = {
                searching = false
                model.searchInside("")
            },
        )
    }
    if (toolsOpen) {
        ChatToolsSheet(
            model,
            onCall = { confirmingCall = true },
            onDeleteChat = { toolsOpen = false; eraseChat = ChatErase.DELETE },
            onClearHistory = { toolsOpen = false; eraseChat = ChatErase.CLEAR },
            onDismiss = { toolsOpen = false },
        )
    }
    if (leaving) {
        val channel = state.header?.type == app.orbitle.domain.ChatType.CHANNEL
        AlertDialog(
            onDismissRequest = { leaving = false },
            title = { Text(if (channel) "Отписаться от канала?" else "Покинуть группу?") },
            text = { Text(if (channel) "Канал пропадёт из списка чатов. Подписаться снова можно через поиск." else "Группа пропадёт из списка чатов. Вернуться можно по ссылке-приглашению.") },
            confirmButton = {
                TextButton(onClick = { leaving = false; model.leave(onBack) }) {
                    Text(if (channel) "Отписаться" else "Покинуть", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { leaving = false }) { Text("Отмена") } },
        )
    }
    eraseChat?.let { kind ->
        val header = state.header
        EraseChatDialog(
            kind = kind,
            type = header?.type ?: app.orbitle.domain.ChatType.PRIVATE,
            saved = header?.isSavedMessages == true,
            title = header?.title.orEmpty(),
            onChoose = { forEveryone ->
                eraseChat = null
                if (kind == ChatErase.DELETE) model.deleteChat(forEveryone, onBack) else model.clearHistory(forEveryone)
            },
            onDismiss = { eraseChat = null },
        )
    }
    if (makingPoll) {
        PollComposerSheet(onSend = model::sendPoll, onDismiss = { makingPoll = false })
    }
    if (scheduling) {
        ScheduleSheet(model, onDismiss = { scheduling = false })
    }
    if (confirmingCall) {
        CallConfirmDialog(
            onAudio = { confirmingCall = false; model.signalCall(false) },
            onVideo = { confirmingCall = false; model.signalCall(true) },
            onDismiss = { confirmingCall = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatTopBar(
    state: ChatUiState,
    onBack: () -> Unit,
    onOpenProfile: () -> Unit,
    privacy: app.orbitle.domain.PrivateModeDisplay = app.orbitle.domain.PrivateModeDisplay.VISIBLE,
) {
    TopAppBar(
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
        title = {
            val real = state.header ?: return@TopAppBar
            val header = if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) app.orbitle.presentation.settings.PrivateModeMask.header(real) else real
            Row(Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onOpenProfile), verticalAlignment = Alignment.CenterVertically) {
                Avatar(header.avatar, 40.dp, modifier = Modifier.privateBlur(privacy, 6.dp))
                Spacer(Modifier.width(12.dp))
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(header.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false).privateBlur(privacy, 7.dp))
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

/** Закрытый пузырь приватного режима: заглушка или размытый пузырь, касание открывает его. */
@Composable
private fun PrivateBubble(item: ChatItem.Bubble, privacy: app.orbitle.domain.PrivateModeDisplay, onReveal: () -> Unit) {
    val shown = remember(item, privacy) {
        if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) app.orbitle.presentation.settings.PrivateModeMask.bubble(item) else item
    }
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.privateBlur(privacy, 12.dp)) {
            BubbleRow(item = shown, onLongPress = {}, onReaction = { _, _ -> }, onReplyClick = {}, onRetry = {})
        }
        // Поверх пузыря: меню, реакции и смахивание закрытого пузыря недоступны.
        Box(
            Modifier
                .matchParentSize()
                .clickable(
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                    indication = null,
                    onClickLabel = "Покажет сообщение на 15 секунд",
                    onClick = onReveal,
                )
                .semantics { contentDescription = app.orbitle.presentation.settings.PrivateModeMask.messageText(item.message, item.outgoing) },
        )
    }
}

/** Капсула «Отключить приватный режим» и подсказка под ней. */
@Composable
private fun PrivateModeCapsule(showsHint: Boolean, onDisable: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Surface(
            onClick = onDisable,
            shape = RoundedCornerShape(50),
            color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
            shadowElevation = 2.dp,
        ) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.VisibilityOff, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text("Отключить приватный режим", style = MaterialTheme.typography.labelLarge)
            }
        }
        if (showsHint) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.85f),
                modifier = Modifier.padding(top = 6.dp, start = 32.dp, end = 32.dp),
            ) {
                Text(
                    app.orbitle.presentation.settings.PrivateModeMask.REVEAL_HINT,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
    }
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
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Composer(
    state: ChatUiState,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
    onCancelReply: () -> Unit,
    onCancelEdit: () -> Unit,
    onAttach: () -> Unit,
    onRemoveAttachment: (OutgoingFile) -> Unit,
    onEditPhoto: (OutgoingFile) -> Unit,
    panel: StickerPanel? = null,
    onSticker: (Sticker) -> Unit = {},
    onAnimoji: (AnimatedEmoji) -> Unit = {},
    onCancelUpload: () -> Unit = {},
    recorder: app.orbitle.media.AndroidVoiceRecorder? = null,
    onVoice: (app.orbitle.domain.VoiceRecording) -> Unit = {},
    onRecordingStart: () -> Unit = {},
    onMention: (app.orbitle.data.ChatMemberRow) -> Unit = {},
    onCommand: (app.orbitle.data.BotCommandRow) -> Unit = {},
) {
    var showPanel by rememberSaveable { mutableStateOf(false) }
    val voice = rememberVoiceRecording(recorder, onVoice, onRecordingStart)
    val hasPanel = panel != null
    val onPanel: (Boolean) -> Unit = { showPanel = it }
    val keyboard = LocalSoftwareKeyboardController.current
    val insertEmoji = remember { mutableStateOf<(String) -> Unit>({}) }
    val imeVisible = WindowInsets.isImeVisible
    // Клавиатура открылась поверх панели: панель уходит.
    LaunchedEffect(imeVisible) { if (imeVisible) showPanel = false }
    BackHandler(enabled = showPanel) { showPanel = false }
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(if (showPanel) Modifier else Modifier.navigationBarsPadding()) {
            val editing = state.editing
            val reply = state.replyTo
            // Приватный режим: панель над полем ввода без автора и текста.
            val masked = app.orbitle.ui.components.LocalPrivateMode.current != app.orbitle.domain.PrivateModeDisplay.VISIBLE
            state.uploadProgress?.let { progress ->
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Отправка вложений… ${(progress * 100).toInt()}%", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.size(4.dp))
                        LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                    }
                    IconButton(onClick = onCancelUpload) { Icon(Icons.Filled.Close, "Отменить отправку") }
                }
            }
            if (state.attachments.isNotEmpty()) {
                AttachmentStrip(state.attachments, onRemoveAttachment, onEditPhoto)
            }
            if (editing != null || reply != null) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (editing != null) Icons.Filled.Edit else Icons.AutoMirrored.Filled.Reply, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            if (editing != null) "Редактирование" else if (masked) "Ответ" else reply!!.authorName.ifEmpty { "Ответ" },
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.labelLarge,
                            maxLines = 1,
                        )
                        val target = (editing ?: reply)!!
                        Text(if (masked) app.orbitle.presentation.settings.PrivateModeMask.panelText(target, editing = editing != null) else target.replySnippet, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(onClick = if (editing != null) onCancelEdit else onCancelReply) { Icon(Icons.Filled.Close, "Отменить") }
                }
            }
            voice.hint?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                )
            }
            ComposerHintsBar(state.hints, onMention, onCommand)
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.Bottom) {
                if (editing == null) {
                    IconButton(onClick = onAttach, modifier = Modifier.size(44.dp)) {
                        Icon(Icons.Filled.AttachFile, "Прикрепить", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Spacer(Modifier.width(2.dp))
                }
                // Текст правки или восстановленный черновик приходит извне: курсор в конец.
                var field by remember { mutableStateOf(TextFieldValue(state.draft, TextRange(state.draft.length))) }
                if (field.text != state.draft) field = TextFieldValue(state.draft, TextRange(state.draft.length))
                val focus = remember { FocusRequester() }
                insertEmoji.value = { emoji ->
                    val start = field.selection.min.coerceIn(0, field.text.length)
                    val end = field.selection.max.coerceIn(0, field.text.length)
                    val text = field.text.substring(0, start) + emoji + field.text.substring(end)
                    field = TextFieldValue(text, TextRange(start + emoji.length))
                    onDraft(text)
                }
                LaunchedEffect(editing?.id, reply?.id) { if ((editing != null || reply != null) && !showPanel) runCatching { focus.requestFocus() } }
                if (voice.live != null) {
                    RecordingBar(voice, Modifier.weight(1f))
                } else Row(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 44.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest),
                    verticalAlignment = Alignment.Bottom,
                ) {
                    Box(Modifier.weight(1f).padding(start = 16.dp, top = 11.dp, bottom = 11.dp, end = 4.dp), contentAlignment = Alignment.CenterStart) {
                        if (state.draft.isEmpty()) Text("Сообщение", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
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
                            modifier = Modifier.fillMaxWidth().focusRequester(focus).onFocusChanged { if (it.isFocused && showPanel) onPanel(false) },
                        )
                    }
                    if (hasPanel) {
                        IconButton(
                            onClick = {
                                if (showPanel) {
                                    onPanel(false)
                                    runCatching { focus.requestFocus() }
                                    keyboard?.show()
                                } else {
                                    keyboard?.hide()
                                    onPanel(true)
                                }
                            },
                            modifier = Modifier.size(44.dp),
                        ) {
                            Icon(
                                if (showPanel) Icons.Outlined.Keyboard else Icons.Outlined.EmojiEmotions,
                                if (showPanel) "Клавиатура" else "Эмодзи и стикеры",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                Spacer(Modifier.width(6.dp))
                val enabled = state.canSend
                // Пустое поле — микрофон: удержание пишет голосовое, как в Max.
                if (recorder != null && !enabled && state.editing == null && state.uploadProgress == null) {
                    MicButton(voice)
                } else Box(
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
            if (showPanel && panel != null) {
                Column(Modifier.navigationBarsPadding()) {
                    StickerPanelView(
                        panel,
                        300.dp,
                        onEmoji = { insertEmoji.value(it) },
                        onSticker = { onSticker(it) },
                        onAnimoji = { emoji ->
                            onAnimoji(emoji)
                            insertEmoji.value(emoji.emoji)
                        },
                    )
                }
            }
        }
    }
}

/** Выбранные вложения над полем ввода, у каждого — крестик. */
@Composable
private fun AttachmentStrip(items: List<OutgoingFile>, onRemove: (OutgoingFile) -> Unit, onEditPhoto: (OutgoingFile) -> Unit) {
    LazyRow(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(items, key = { it.path }) { item ->
            Box(Modifier.size(72.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest)) {
                when (item.kind) {
                    OutgoingFile.Kind.PHOTO -> AsyncImage(File(item.path), "Редактировать фото: ${item.name}", Modifier.fillMaxSize().clickable { onEditPhoto(item) }, contentScale = ContentScale.Crop)
                    OutgoingFile.Kind.VIDEO -> Icon(Icons.Filled.Videocam, item.name, Modifier.align(Alignment.Center), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutgoingFile.Kind.FILE -> Column(Modifier.align(Alignment.Center).padding(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Outlined.InsertDriveFile, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(item.name, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                    }
                }
                Box(
                    Modifier.align(Alignment.TopEnd).padding(3.dp).size(22.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).clickable { onRemove(item) },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Close, "Убрать", tint = Color.White, modifier = Modifier.size(14.dp)) }
                if (item.kind == OutgoingFile.Kind.PHOTO) {
                    Box(Modifier.align(Alignment.BottomStart).padding(3.dp).size(24.dp).clip(CircleShape).background(Color.Black.copy(alpha = .55f)).clickable { onEditPhoto(item) }, contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Edit, "Редактировать фото", tint = Color.White, modifier = Modifier.size(14.dp))
                    }
                }
            }
        }
    }
}

/** Что прикрепить: фото и видео из галереи или любой файл. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AttachSheet(
    onDismiss: () -> Unit,
    onMedia: () -> Unit,
    onFile: () -> Unit,
    onPoll: () -> Unit,
    onSchedule: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        val colors = ListItemDefaults.colors(containerColor = Color.Transparent)
        ListItem(
            headlineContent = { Text("Фото или видео") },
            supportingContent = { Text("Из галереи, до ${OutgoingFile.LIMIT} за раз") },
            leadingContent = { Icon(Icons.Outlined.Image, null, tint = MaterialTheme.colorScheme.primary) },
            colors = colors,
            modifier = Modifier.clickable(onClick = onMedia),
        )
        ListItem(
            headlineContent = { Text("Файл") },
            supportingContent = { Text("Документ любого типа") },
            leadingContent = { Icon(Icons.Outlined.InsertDriveFile, null, tint = MaterialTheme.colorScheme.primary) },
            colors = colors,
            modifier = Modifier.clickable(onClick = onFile),
        )
        ListItem(
            headlineContent = { Text("Опрос") },
            supportingContent = { Text("Вопрос и ответы") },
            leadingContent = { Icon(Icons.Outlined.Poll, null, tint = MaterialTheme.colorScheme.primary) },
            colors = colors,
            modifier = Modifier.clickable(onClick = onPoll),
        )
        ListItem(
            headlineContent = { Text("Отложить") },
            supportingContent = { Text("Отправить текст из поля позже") },
            leadingContent = { Icon(Icons.Outlined.Schedule, null, tint = MaterialTheme.colorScheme.primary) },
            colors = colors,
            modifier = Modifier.clickable(onClick = onSchedule),
        )
        Spacer(Modifier.size(24.dp))
    }
}

/** Меню сообщения: быстрые реакции и действия. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MessageActions(
    model: ChatViewModel,
    message: Message,
    onDismiss: () -> Unit,
    onDelete: () -> Unit,
    onForward: () -> Unit,
    onReactionUsers: () -> Unit,
    onSave: (SaveTarget) -> Unit,
    /** Пометить чат непрочитанным с этого сообщения и закрыть его. */
    onMarkUnread: () -> Unit,
) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val clipboard = LocalClipboardManager.current
    val catalog = model.state.collectAsStateWithLifecycle().value.reactionCatalog
    var allReactions by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        if (model.canReact(message) && allReactions) {
            ReactionGrid(catalog, message.content.reactions.firstOrNull { it.mine }?.emoji) { emoji ->
                model.toggleReaction(message, emoji)
                onDismiss()
            }
            Spacer(Modifier.size(16.dp))
            return@ModalBottomSheet
        }
        if (model.canReact(message)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
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
                if (catalog.size > ReactionPalette.QUICK_COUNT) {
                    IconButton(onClick = { allReactions = true }, modifier = Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest)) {
                        Icon(Icons.Filled.KeyboardArrowDown, "Все реакции")
                    }
                }
            }
        }
        val colors = ListItemDefaults.colors(containerColor = Color.Transparent)
        if (model.canShowReactionUsers(message)) {
            ListItem(
                headlineContent = { Text("Кто отреагировал") },
                leadingContent = { Icon(Icons.Outlined.Group, null) },
                colors = colors,
                modifier = Modifier.clickable { onDismiss(); onReactionUsers() },
            )
        }
        if (model.canCancelUpload(message)) {
            ListItem(
                headlineContent = { Text("Отменить отправку") },
                leadingContent = { Icon(Icons.Filled.Close, null) },
                colors = colors,
                modifier = Modifier.clickable { model.cancelUpload(message); onDismiss() },
            )
        }
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
        if (model.canOpenComments(message)) {
            ListItem(
                headlineContent = { Text("Комментарии") },
                leadingContent = { Icon(Icons.AutoMirrored.Outlined.Comment, null) },
                colors = colors,
                modifier = Modifier.clickable { onDismiss(); model.openComments(message) },
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
        if (model.media.canSave(message, SaveTarget.GALLERY)) {
            ListItem(
                headlineContent = { Text("Сохранить в галерею") },
                leadingContent = { Icon(Icons.Outlined.Download, null) },
                colors = colors,
                modifier = Modifier.clickable { onDismiss(); onSave(SaveTarget.GALLERY) },
            )
        }
        if (model.media.canSave(message, SaveTarget.DOWNLOADS)) {
            ListItem(
                headlineContent = { Text("Сохранить в «Загрузки»") },
                leadingContent = { Icon(Icons.Outlined.Folder, null) },
                colors = colors,
                modifier = Modifier.clickable { onDismiss(); onSave(SaveTarget.DOWNLOADS) },
            )
        }
        if (model.canForward(message)) {
            ListItem(
                headlineContent = { Text("Переслать") },
                leadingContent = { Icon(Icons.AutoMirrored.Filled.Forward, null) },
                colors = colors,
                modifier = Modifier.clickable { onDismiss(); onForward() },
            )
        }
        if (model.canPin(message)) {
            ListItem(
                headlineContent = { Text("Закрепить") },
                leadingContent = { Icon(Icons.Filled.PushPin, null) },
                colors = colors,
                modifier = Modifier.clickable { model.pin(message); onDismiss() },
            )
        }
        if (model.canMarkUnread(message)) {
            ListItem(
                headlineContent = { Text("Пометить непрочитанным") },
                leadingContent = { Icon(Icons.Outlined.MarkChatUnread, null) },
                colors = colors,
                modifier = Modifier.clickable { onDismiss(); onMarkUnread() },
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

/** Состояние записи голосового в поле ввода. */
private class VoiceRecordingUi(
    val live: app.orbitle.media.AndroidVoiceRecorder.Live?,
    val locked: Boolean,
    val dragX: Float,
    val hint: String?,
    val gesture: Modifier,
    val onCancel: () -> Unit,
)

@Composable
private fun rememberVoiceRecording(
    recorder: app.orbitle.media.AndroidVoiceRecorder?,
    onVoice: (app.orbitle.domain.VoiceRecording) -> Unit,
    onStart: () -> Unit,
): VoiceRecordingUi {
    val context = LocalContext.current
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    val flow = remember(recorder) { recorder?.live ?: kotlinx.coroutines.flow.MutableStateFlow(null) }
    val live by flow.collectAsStateWithLifecycle()
    var locked by remember { mutableStateOf(false) }
    var dragX by remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    var hint by remember { mutableStateOf<String?>(null) }
    val send by androidx.compose.runtime.rememberUpdatedState(onVoice)
    val start by androidx.compose.runtime.rememberUpdatedState(onStart)
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hint = if (granted) app.orbitle.presentation.chat.RecordingGesture.HOLD_HINT else "Нет доступа к микрофону"
    }
    LaunchedEffect(hint) {
        if (hint != null) {
            delay(2_500)
            hint = null
        }
    }
    // Уход из чата обрывает запись: ничего не уходит.
    androidx.compose.runtime.DisposableEffect(recorder) { onDispose { recorder?.cancel() } }
    val finish = {
        locked = false
        dragX = 0f
        val result = recorder?.finish(app.orbitle.presentation.chat.RecordingGesture.MINIMUM_DURATION_MS)
        if (result != null) send(result) else hint = app.orbitle.presentation.chat.RecordingGesture.HOLD_HINT
    }
    val cancel = {
        locked = false
        dragX = 0f
        recorder?.cancel()
        Unit
    }
    val gesture = Modifier.pointerInput(recorder) {
        val rec = recorder ?: return@pointerInput
        awaitEachGesture {
            val down = awaitFirstDown()
            if (locked) {
                // Закреплённая запись: кнопка отправляет.
                if (waitForUpOrCancellation() != null) finish()
                return@awaitEachGesture
            }
            val granted = androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) {
                waitForUpOrCancellation()
                permission.launch(android.Manifest.permission.RECORD_AUDIO)
                return@awaitEachGesture
            }
            start()
            if (!rec.start()) {
                hint = "Не удалось включить микрофон"
                return@awaitEachGesture
            }
            val origin = down.position
            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == down.id } ?: run {
                    cancel()
                    break
                }
                val dx = (change.position.x - origin.x) / density
                val dy = (change.position.y - origin.y) / density
                if (!change.pressed) {
                    val elapsed = rec.live.value?.elapsedMs ?: 0L
                    when (app.orbitle.presentation.chat.RecordingGesture.released(dx, dy, elapsed)) {
                        app.orbitle.presentation.chat.RecordingGesture.Outcome.SEND -> finish()
                        else -> {
                            cancel()
                            if (elapsed < app.orbitle.presentation.chat.RecordingGesture.MINIMUM_DURATION_MS) {
                                hint = app.orbitle.presentation.chat.RecordingGesture.HOLD_HINT
                            }
                        }
                    }
                    break
                }
                change.consume()
                when (app.orbitle.presentation.chat.RecordingGesture.during(dx, dy)) {
                    app.orbitle.presentation.chat.RecordingGesture.Outcome.CANCEL -> {
                        cancel()
                        waitForUpOrCancellation()
                        break
                    }
                    app.orbitle.presentation.chat.RecordingGesture.Outcome.LOCK -> {
                        locked = true
                        dragX = 0f
                        waitForUpOrCancellation()
                        break
                    }
                    else -> dragX = minOf(0f, dx)
                }
            }
        }
    }
    return VoiceRecordingUi(live, locked, dragX, hint, gesture, cancel)
}

@Composable
private fun MicButton(voice: VoiceRecordingUi) {
    val recording = voice.live != null
    Box(contentAlignment = Alignment.Center) {
        if (recording && !voice.locked) {
            // Подсказка закрепления над кнопкой.
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier.offset(y = (-64).dp).size(width = 32.dp, height = 48.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Lock, "Вверх — закрепить", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Box(
            Modifier
                .size(if (recording && !voice.locked) 52.dp else 44.dp)
                .clip(CircleShape)
                .background(if (recording) OrbitleAccent else MaterialTheme.colorScheme.surfaceContainerHighest)
                .then(voice.gesture)
                .semantics { contentDescription = if (voice.locked) "Отправить голосовое" else "Голосовое: удерживайте, чтобы записать" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (voice.locked) Icons.AutoMirrored.Filled.Send else Icons.Filled.Mic,
                null,
                tint = if (recording) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun RecordingBar(voice: VoiceRecordingUi, modifier: Modifier) {
    val live = voice.live ?: return
    val level by androidx.compose.animation.core.animateFloatAsState(live.level, label = "level")
    Row(
        modifier
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(10.dp)
                .graphicsLayer { scaleX = 1f + level * 0.6f; scaleY = scaleX }
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.error),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            app.orbitle.presentation.chat.CallBubbleText.clock(live.elapsedMs),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.semantics { contentDescription = "Идёт запись" },
        )
        Spacer(Modifier.weight(1f))
        if (voice.locked) {
            TextButton(onClick = voice.onCancel) {
                Icon(Icons.Outlined.Delete, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(4.dp))
                Text("Отмена", color = MaterialTheme.colorScheme.error)
            }
        } else {
            val progress = app.orbitle.presentation.chat.RecordingGesture.cancelProgress(voice.dragX)
            Text(
                "‹ Влево — отмена",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.graphicsLayer { translationX = voice.dragX * density; alpha = 1f - progress * 0.8f },
            )
        }
    }
}
