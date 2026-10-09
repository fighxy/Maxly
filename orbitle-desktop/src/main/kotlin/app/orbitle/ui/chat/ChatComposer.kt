package app.orbitle.ui.chat

// Поле ввода чата: текст, вложения, панель стикеров, запись голосового.

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
import app.orbitle.platform.BackHandler
import androidx.compose.material.icons.outlined.EmojiEmotions
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.Sticker
import app.orbitle.presentation.stickers.StickerPanel
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.automirrored.outlined.InsertDriveFile
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
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import app.orbitle.ui.components.AppSheet
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
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
import app.orbitle.domain.TextSpan
import app.orbitle.domain.MessageStatus
import app.orbitle.media.AttachmentImporter
import app.orbitle.media.DesktopVoiceRecorder
import app.orbitle.platform.DesktopActions
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

/** Поле ввода с плашкой ответа или правки. */
@Composable
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
internal fun Composer(
    state: ChatUiState,
    /** Новый текст поля и курсор после правки (по нему разметка понимает, где набрали). */
    onDraft: (String, Int) -> Unit,
    onSend: () -> Unit,
    /** Долгое нажатие на «Отправить»: выбрать время отложенной отправки; `null` — нельзя. */
    onScheduleSend: (() -> Unit)? = null,
    onCancelReply: () -> Unit,
    onCancelEdit: () -> Unit,
    onAttach: () -> Unit,
    /** Меню вложений у скрепки: рисуется рядом с кнопкой, открытым его держит экран. */
    attachMenu: @Composable () -> Unit = {},
    onRemoveAttachment: (OutgoingFile) -> Unit,
    onEditPhoto: (OutgoingFile) -> Unit,
    panel: StickerPanel? = null,
    onSticker: (Sticker) -> Unit = {},
    onAnimoji: (AnimatedEmoji) -> Unit = {},
    onCancelUpload: () -> Unit = {},
    /** Запись голосового или кружка кнопкой справа; `null` — без записи. */
    recording: app.orbitle.presentation.chat.RecordingController? = null,
    recordingLive: kotlinx.coroutines.flow.StateFlow<app.orbitle.ui.chat.RecordingLive?>? = null,
    /** Превью камеры, пока пишется кружок. */
    videoPreview: (@Composable (Modifier) -> Unit)? = null,
    onMention: (app.orbitle.data.ChatMemberRow) -> Unit = {},
    onCommand: (app.orbitle.data.BotCommandRow) -> Unit = {},
    /** Кнопка или сочетание форматирования для выделения [start, end) поля. */
    onToggleFormat: (TextSpan.Kind, Int, Int) -> Unit = { _, _, _ -> },
    /** Ссылка на выделении [start, end): адрес или `null` — убрать. */
    onLink: (Int, Int, String?) -> Unit = { _, _, _ -> },
    /** Адрес ссылки, стоящей ровно на выделении; `null` — ссылки нет. */
    linkAt: (Int, Int) -> String? = { _, _ -> null },
    /** ↑ в пустом поле: правка своего последнего сообщения. `false` — править нечего. */
    onEditLast: () -> Boolean = { false },
    /** Ctrl+V / Shift+Insert: `true` — из буфера взяты файлы или картинка, текст не вставляется. */
    onPaste: () -> Boolean = { false },
) {
    var showPanel by rememberSaveable { mutableStateOf(false) }
    val sendKey = app.orbitle.ui.keys.LocalSendKey.current
    val voice = app.orbitle.ui.chat.rememberRecordingUi(recording, recordingLive)
    val hasPanel = panel != null
    val onPanel: (Boolean) -> Unit = { showPanel = it }
    val keyboard = LocalSoftwareKeyboardController.current
    val insertEmoji = remember { mutableStateOf<(String) -> Unit>({}) }
    // Текст правки или восстановленный черновик приходит извне: курсор в конец.
    var field by remember { mutableStateOf(TextFieldValue(state.draft, TextRange(state.draft.length))) }
    if (field.text != state.draft) field = TextFieldValue(state.draft, TextRange(state.draft.length))
    val focus = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    // Панель форматирования: открыта кнопкой «Aa» или сама, пока в поле выделен текст.
    var formatOpen by rememberSaveable { mutableStateOf(false) }
    // Выделение, для которого открыт диалог ссылки: в диалоге фокус уходит из поля.
    var linkRange by remember { mutableStateOf<TextRange?>(null) }
    val toggleFormat: (TextSpan.Kind) -> Unit = { kind ->
        val selection = field.selection
        if (!selection.collapsed) onToggleFormat(kind, selection.min, selection.max)
    }
    val openLink: () -> Unit = { if (!field.selection.collapsed) linkRange = field.selection }
    // Сочетания форматирования, пока фокус в поле и в нём выделен текст. Без выделения
    // сочетание идёт дальше: Ctrl+K остаётся поиском по чатам.
    app.orbitle.ui.keys.HotkeyHandler(enabled = focused) { hotkey ->
        if (field.selection.collapsed || linkRange != null) return@HotkeyHandler false
        when (hotkey.action) {
            app.orbitle.ui.keys.HotkeyAction.FORMAT_BOLD -> toggleFormat(TextSpan.Kind.STRONG)
            app.orbitle.ui.keys.HotkeyAction.FORMAT_ITALIC -> toggleFormat(TextSpan.Kind.EMPHASIZED)
            app.orbitle.ui.keys.HotkeyAction.FORMAT_UNDERLINE -> toggleFormat(TextSpan.Kind.UNDERLINE)
            app.orbitle.ui.keys.HotkeyAction.FORMAT_STRIKE -> toggleFormat(TextSpan.Kind.STRIKETHROUGH)
            app.orbitle.ui.keys.HotkeyAction.FORMAT_MONO -> toggleFormat(TextSpan.Kind.MONOSPACED)
            app.orbitle.ui.keys.HotkeyAction.SEARCH_CHATS -> openLink()
            else -> return@HotkeyHandler false
        }
        true
    }
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
            if (voice.state.isVideo && videoPreview != null) {
                // Кружок пишется: превью камеры кругом над полем ввода, как на iOS.
                Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                    videoPreview(Modifier.size(220.dp).clip(CircleShape))
                }
            }
            voice.state.hint?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                )
            }
            ComposerHintsBar(state.hints, onMention, onCommand)
            if (!voice.state.isActive && (formatOpen || (focused && !field.selection.collapsed))) {
                FormatBar(
                    state.formatting,
                    field.selection,
                    onToggle = toggleFormat,
                    onLink = openLink,
                    modifier = Modifier.padding(top = 4.dp),
                    hints = formatHints(),
                )
            }
            linkRange?.let { range ->
                LinkDialog(
                    current = linkAt(range.min, range.max),
                    onDone = { url ->
                        linkRange = null
                        onLink(range.min, range.max, url)
                        // Вернуть выделение и фокус в поле.
                        if (range.max <= field.text.length) field = field.copy(selection = range)
                        runCatching { focus.requestFocus() }
                    },
                    onDismiss = {
                        linkRange = null
                        runCatching { focus.requestFocus() }
                    },
                )
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.Bottom) {
                if (editing == null) {
                    Box {
                        IconButton(onClick = onAttach, modifier = Modifier.size(44.dp)) {
                            Icon(Icons.Filled.AttachFile, "Прикрепить", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        attachMenu()
                    }
                    Spacer(Modifier.width(2.dp))
                }
                insertEmoji.value = { emoji ->
                    val start = field.selection.min.coerceIn(0, field.text.length)
                    val end = field.selection.max.coerceIn(0, field.text.length)
                    val text = field.text.substring(0, start) + emoji + field.text.substring(end)
                    field = TextFieldValue(text, TextRange(start + emoji.length))
                    onDraft(text, start + emoji.length)
                }
                LaunchedEffect(editing?.id, reply?.id) { if ((editing != null || reply != null) && !showPanel) runCatching { focus.requestFocus() } }
                if (voice.state.isActive) {
                    app.orbitle.ui.chat.RecordingBar(voice, Modifier.weight(1f))
                } else Row(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 44.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest),
                    verticalAlignment = Alignment.Bottom,
                ) {
                    val linkColor = MaterialTheme.colorScheme.primary
                    Box(Modifier.weight(1f).padding(start = 16.dp, top = 11.dp, bottom = 11.dp, end = 4.dp), contentAlignment = Alignment.CenterStart) {
                        if (state.draft.isEmpty()) Text("Сообщение", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
                        BasicTextField(
                            value = field,
                            onValueChange = {
                                field = it
                                if (it.text != state.draft) onDraft(it.text, it.selection.max)
                            },
                            visualTransformation = remember(state.formatting, linkColor) { FormattingTransformation(state.formatting, linkColor) },
                            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, fontSize = 16.sp),
                            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                            maxLines = 6,
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(focus)
                                .onFocusChanged {
                                    focused = it.isFocused
                                    if (it.isFocused && showPanel) onPanel(false)
                                }
                                .onPreviewKeyEvent { composerKey(it, sendKey, field.text.isEmpty(), state.canSend, onSend, onEditLast, onPaste) },
                        )
                    }
                    FormatToggle(formatOpen, onToggle = { formatOpen = !formatOpen })
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
                if (recording != null && (voice.state.isActive || (!enabled && state.editing == null && state.uploadProgress == null))) {
                    app.orbitle.ui.chat.RecordButton(voice)
                } else Box(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest)
                        .combinedClickable(
                            enabled = enabled,
                            onLongClick = onScheduleSend?.takeIf { state.editing == null && state.attachments.isEmpty() },
                            onClick = onSend,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (state.editing != null) Icons.Filled.Check else Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Отправить",
                        tint = if (enabled) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
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

/** Подписи сочетаний клавиш у кнопок панели форматирования. */
private fun formatHints(): Map<TextSpan.Kind, String> {
    val command = app.orbitle.ui.keys.KeyChords.command
    return mapOf(
        TextSpan.Kind.STRONG to "$command+B",
        TextSpan.Kind.EMPHASIZED to "$command+I",
        TextSpan.Kind.UNDERLINE to "$command+U",
        TextSpan.Kind.STRIKETHROUGH to "$command+Shift+X",
        TextSpan.Kind.MONOSPACED to "$command+Shift+M",
        TextSpan.Kind.LINK to "$command+K",
    )
}

/** Выбранные вложения над полем ввода, у каждого — крестик. */
@Composable
internal fun AttachmentStrip(items: List<OutgoingFile>, onRemove: (OutgoingFile) -> Unit, onEditPhoto: (OutgoingFile) -> Unit) {
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
                        Icon(Icons.AutoMirrored.Outlined.InsertDriveFile, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
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
/**
 * Меню вложений — выпадает у скрепки, как в Telegram Desktop: фото и видео, файл, опрос,
 * отложенное. Картинку и файлы можно и вставить из буфера (Ctrl+V).
 */
@Composable
internal fun AttachMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    onMedia: () -> Unit,
    onFile: () -> Unit,
    onPoll: () -> Unit,
    onSchedule: () -> Unit,
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        val tint = MaterialTheme.colorScheme.primary
        DropdownMenuItem(
            text = { Text("Фото или видео") },
            leadingIcon = { Icon(Icons.Outlined.Image, null, tint = tint) },
            onClick = onMedia,
        )
        DropdownMenuItem(
            text = { Text("Файл") },
            leadingIcon = { Icon(Icons.AutoMirrored.Outlined.InsertDriveFile, null, tint = tint) },
            onClick = onFile,
        )
        DropdownMenuItem(
            text = { Text("Опрос") },
            leadingIcon = { Icon(Icons.Outlined.Poll, null, tint = tint) },
            onClick = onPoll,
        )
        DropdownMenuItem(
            text = { Text("Отложить сообщение") },
            leadingIcon = { Icon(Icons.Outlined.Schedule, null, tint = tint) },
            onClick = onSchedule,
        )
    }
}


/**
 * Клавиши поля ввода: отправка выбранной клавишей ([SendKey]: Enter или
 * Ctrl+Enter; другая даёт новую строку) и ↑ в пустом поле — правка своего последнего сообщения.
 */
private fun composerKey(
    event: androidx.compose.ui.input.key.KeyEvent,
    sendKey: app.orbitle.ui.keys.SendKey,
    empty: Boolean,
    canSend: Boolean,
    onSend: () -> Unit,
    onEditLast: () -> Boolean,
    onPaste: () -> Boolean,
): Boolean {
    if (event.type != KeyEventType.KeyDown) return false
    val command = event.isCtrlPressed || event.isMetaPressed
    return when (event.key) {
        Key.Enter, Key.NumPadEnter -> {
            val sends = when (sendKey) {
                app.orbitle.ui.keys.SendKey.ENTER -> !event.isShiftPressed && !command && !event.isAltPressed
                app.orbitle.ui.keys.SendKey.CTRL_ENTER -> command
            }
            if (sends && canSend) onSend()
            sends
        }
        Key.DirectionUp -> empty && !command && !event.isShiftPressed && !event.isAltPressed && onEditLast()
        // Скриншот или файлы из проводника — вложениями; текст поле вставит само.
        Key.V -> command && !event.isAltPressed && onPaste()
        Key.Insert -> event.isShiftPressed && !command && onPaste()
        else -> false
    }
}
