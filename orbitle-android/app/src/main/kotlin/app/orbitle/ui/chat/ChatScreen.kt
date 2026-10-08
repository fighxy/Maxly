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
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
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
    /** Сообщение из общего поиска и его время (мс, 0 — неизвестно): чат открывается на нём. */
    openMessage: Pair<String, Long>? = null,
    onMessageOpened: () -> Unit = {},
    /** Мини-приложение бота поверх чата: кнопка «Открыть приложение» и inline-кнопки `OPEN_APP`. */
    botApp: @Composable (request: BotAppRequest, onClose: () -> Unit) -> Unit = { _, onClose -> onClose() },
    /** Блок автора комментария под постом канала. Ошибку показывает экран комментариев. */
    onBlockComment: suspend (postId: String, comment: Message) -> Unit = { _, _ -> },
    /** Позвонить собеседнику: звонок ведёт центр звонков приложения. */
    onStartCall: (peer: app.orbitle.presentation.calls.CallPeerInfo, video: Boolean) -> Unit = { _, _ -> },
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
    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    val composerRecorder = remember {
        app.orbitle.media.AndroidComposerRecorder(
            voiceRecorder,
            app.orbitle.media.AndroidVideoNoteRecorder(context.applicationContext, lifecycleOwner),
            recorderScope,
        )
    }
    // Голосовое или кружок: режим кнопки запоминается на устройстве.
    val recording = remember {
        val prefs = context.getSharedPreferences("orbitle.chat", android.content.Context.MODE_PRIVATE)
        val store = object : app.orbitle.data.PreferenceStore {
            override fun get(key: String): String? = prefs.getString(key, null)
            override fun put(key: String, value: String) = prefs.edit().putString(key, value).apply()
        }
        app.orbitle.presentation.chat.RecordingController(composerRecorder, recorderScope, app.orbitle.presentation.chat.RecordingModeSettings(store))
    }
    recording.onRecorded = model::sendRecorded
    recording.onStart = model.media::stopVoice
    // Уход из чата обрывает запись: ничего не уходит.
    androidx.compose.runtime.DisposableEffect(recording) { onDispose { recording.cancel() } }
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
    val scope = rememberCoroutineScope()
    var actionsFor by remember { mutableStateOf<Message?>(null) }
    var deleting by remember { mutableStateOf<Message?>(null) }
    var forwarding by remember { mutableStateOf<Message?>(null) }
    var reactionUsers by remember { mutableStateOf<app.orbitle.presentation.chat.ReactionUsersModel?>(null) }
    var searching by remember { mutableStateOf(false) }
    var toolsOpen by remember { mutableStateOf(false) }
    var eraseChat by remember { mutableStateOf<ChatErase?>(null) }
    var makingPoll by remember { mutableStateOf(false) }
    var scheduling by remember { mutableStateOf(false) }
    var confirmingCall by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }
    // Закреп и поиск: к сообщению посередине экрана, далёкое грузится окном вокруг него.
    val scrollToMessage: (String) -> Unit = { id -> model.jumpTo(id) }
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
    LaunchedEffect(openMessage) {
        val (id, at) = openMessage ?: return@LaunchedEffect
        model.openAt(id, at)
        onMessageOpened()
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
            ChatAction.JOIN -> model.join()
        }
        onActionHandled()
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
            ChatFeed(
                model = model,
                state = state,
                privacy = privacy,
                revealed = revealed,
                onReveal = reveal,
                onLongPress = { actionsFor = it },
                onRetry = { actionsFor = it },
                quickReaction = quickReaction,
                onButton = pressButton,
                onDisablePrivateMode = onDisablePrivateMode,
                modifier = Modifier.weight(1f).fillMaxWidth(),
            )
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
                    recording = recording,
                    recordingLive = composerRecorder.live,
                    videoPreview = { modifier ->
                        androidx.compose.ui.viewinterop.AndroidView(
                            factory = {
                                val view = composerRecorder.note.preview
                                (view.parent as? android.view.ViewGroup)?.removeView(view)
                                view
                            },
                            modifier = modifier,
                        )
                    },
                    onMention = model::insertMention,
                    onCommand = model::insertCommand,
                )
            } else if (state.join != null) {
                val join = state.join!!
                // Канал или группа вне списка (из поиска): вступление вместо поля ввода.
                ReadOnlyBar {
                    Button(onClick = model::join, enabled = !join.busy, contentPadding = PaddingValues(horizontal = 28.dp)) {
                        if (join.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(join.label)
                    }
                }
            } else if (state.muted != null) {
                // Подписан, а писать нельзя (канал): звук по центру, поиск — круг справа.
                ReadOnlyBar {
                    ChannelSoundSearchBar(
                        muted = state.muted == true,
                        onToggleMute = model::toggleMute,
                        onSearch = { searching = true },
                    )
                }
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
                onBlockAuthor = { comment -> onBlockComment(comments.post.id, comment) },
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
            onAudio = { confirmingCall = false; model.callPeer()?.let { onStartCall(it, false) } },
            onVideo = { confirmingCall = false; model.callPeer()?.let { onStartCall(it, true) } },
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
                val stories = app.orbitle.ui.stories.LocalStoryRings.current
                androidx.compose.runtime.LaunchedEffect(header.storyOwnerId, header.storyOwnerType) {
                    stories.loadOwner(header.storyOwnerId, header.storyOwnerType)
                }
                val ring = if (privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER) null else stories.ringFor(header.storyOwnerId, header.storyOwnerType)
                app.orbitle.ui.stories.StoryRingAvatar(
                    header.avatar, ring, 40.dp, modifier = Modifier.privateBlur(privacy, 6.dp),
                    onRingClick = header.storyOwnerId?.let { owner -> { stories.open(owner) } },
                )
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

/** Вместо поля ввода, когда писать нельзя: одна небольшая кнопка по центру. */
@Composable
private fun ReadOnlyBar(content: @Composable () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Box(Modifier.fillMaxWidth().navigationBarsPadding().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
            content()
        }
    }
}
