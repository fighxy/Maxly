package app.orbitle.ui.chat

// Меню сообщения по долгому нажатию и подтверждение удаления.

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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Меню сообщения: быстрые реакции и действия. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MessageActions(
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
internal fun DeleteDialog(model: ChatViewModel, message: Message, onDismiss: () -> Unit) {
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
