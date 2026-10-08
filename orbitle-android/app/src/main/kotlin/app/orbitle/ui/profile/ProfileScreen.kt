package app.orbitle.ui.profile

import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.automirrored.outlined.ExitToApp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.ChatProfile
import app.orbitle.domain.SharedMediaTab
import app.orbitle.presentation.profile.InfoRow
import app.orbitle.presentation.profile.ProfileUiState
import app.orbitle.presentation.profile.ProfileViewModel
import app.orbitle.presentation.profile.SharedMedia
import app.orbitle.ui.chat.FileOpener
import app.orbitle.ui.chat.MediaViewer
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.theme.AvatarPalette
import coil3.compose.AsyncImage

/**
 * Действия чата, из которого открыт профиль. Раньше они были кнопками «Поиск» и «Ещё» в шапке
 * чата. Профиль закрывается, и действие открывается на экране чата ([app.orbitle.ui.chat.ChatAction]).
 */
class ProfileChatActions(
    val onSearch: () -> Unit,
    /** Участники, общие чаты и жалоба. */
    val onTools: () -> Unit,
    val onCall: () -> Unit,
    val onClearHistory: () -> Unit,
    val onDeleteChat: () -> Unit,
    /** Выйти из группы или отписаться от канала. `null` — не участник (открыт из поиска). */
    val onLeave: (() -> Unit)? = null,
    /** «Подписаться» или «Вступить» у канала или группы вне списка (открыты из поиска). */
    val onJoin: (() -> Unit)? = null,
)

/** Профиль: шапка, сведения, команды бота и общие медиа по вкладкам. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    model: ProfileViewModel,
    onBack: () -> Unit,
    onWrite: (() -> Unit)? = null,
    mediaUserAgent: String = "",
    /** Профиль открыт из чата: поиск, звонок и действия с чатом. */
    chatActions: ProfileChatActions? = null,
    /** Группа или канал: название, участники, ссылка, права. */
    onManage: (() -> Unit)? = null,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val notice by model.notice.collectAsStateWithLifecycle()
    val mediaState by model.media.state.collectAsStateWithLifecycle()
    val playback by model.media.playback.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val list = rememberLazyListState()
    var confirmingBlock by remember { mutableStateOf(false) }
    if (confirmingBlock) {
        AlertDialog(
            onDismissRequest = { confirmingBlock = false },
            title = { Text("Заблокировать ${state.title}?") },
            text = { Text("Пользователь не сможет писать вам и звонить. Разблокировать можно здесь же или в «Конфиденциальности».") },
            confirmButton = {
                TextButton(onClick = { confirmingBlock = false; model.toggleBlocked() }) {
                    Text("Заблокировать", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmingBlock = false }) { Text("Отмена") } },
        )
    }

    LaunchedEffect(notice) {
        val text = notice ?: return@LaunchedEffect
        snackbar.showSnackbar(text)
        model.consumeNotice()
    }
    LaunchedEffect(mediaState.openFile) {
        val file = mediaState.openFile ?: return@LaunchedEffect
        model.media.consumeOpenFile()
        if (!FileOpener.open(context, file)) model.notify("Нет приложения, чтобы открыть этот файл")
    }
    LaunchedEffect(list) {
        snapshotFlow { list.layoutInfo.visibleItemsInfo.lastOrNull()?.index to list.layoutInfo.totalItemsCount }
            .collect { (last, total) -> if (last != null && total > 0 && last >= total - 3) model.loadMore() }
    }

    fun act(row: InfoRow) {
        when (val action = row.action) {
            is InfoRow.Action.Call -> start(context, Intent(Intent.ACTION_DIAL, Uri.parse(action.uri)))
            is InfoRow.Action.Open -> start(context, Intent(Intent.ACTION_VIEW, Uri.parse(action.url)))
            InfoRow.Action.Copy -> {
                clipboard.setText(AnnotatedString(row.value))
                model.notify("Скопировано")
            }
            null -> Unit
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest),
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = MaterialTheme.colorScheme.surfaceContainerLowest,
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = 24.dp)) {
            item(key = "header") { Header(state) }
            item(key = "actions") {
                val share = state.profile.link
                val canWrite = onWrite != null && state.profile.kind in setOf(ChatProfile.Kind.USER, ChatProfile.Kind.BOT, ChatProfile.Kind.SAVED)
                val canCall = chatActions != null && state.profile.kind == ChatProfile.Kind.USER
                if (canWrite || share != null || chatActions != null) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        val join = chatActions?.onJoin?.takeIf { state.profile.link != null }
                        if (join != null && state.profile.kind == ChatProfile.Kind.CHANNEL) {
                            ActionButton("Подписаться", { Icon(Icons.Outlined.AddCircle, null) }, Modifier.weight(1f)) { join() }
                        } else if (join != null && state.profile.kind == ChatProfile.Kind.GROUP) {
                            ActionButton("Вступить", { Icon(Icons.Outlined.AddCircle, null) }, Modifier.weight(1f)) { join() }
                        }
                        if (canWrite) ActionButton("Написать", { Icon(Icons.AutoMirrored.Outlined.Chat, null) }, Modifier.weight(1f)) { onWrite?.invoke() }
                        if (canCall) ActionButton("Звонок", { Icon(Icons.Outlined.Phone, null) }, Modifier.weight(1f)) { chatActions?.onCall?.invoke() }
                        if (chatActions != null) ActionButton("Поиск", { Icon(Icons.Outlined.Search, null) }, Modifier.weight(1f)) { chatActions.onSearch() }
                        if (share != null) ActionButton("Поделиться", { Icon(Icons.Outlined.Share, null) }, Modifier.weight(1f)) {
                            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, share)
                            start(context, Intent.createChooser(send, state.title))
                        }
                        // Отписка от канала на виду, плиткой; выход из группы — в «Ещё».
                        val leave = chatActions?.onLeave
                        if (leave != null && state.profile.kind == ChatProfile.Kind.CHANNEL) {
                            ActionButton("Отписаться", { Icon(Icons.AutoMirrored.Outlined.ExitToApp, null) }, Modifier.weight(1f)) { leave() }
                        }
                        if (chatActions != null) MoreChatActions(chatActions, Modifier.weight(1f), leavesGroup = state.profile.kind == ChatProfile.Kind.GROUP)
                    }
                }
            }
            if (state.rows.isNotEmpty()) {
                item(key = "info") {
                    Card {
                        state.rows.forEachIndexed { index, row ->
                            Column(
                                Modifier.fillMaxWidth().clickable(enabled = row.action != null) { act(row) }.padding(horizontal = 16.dp, vertical = 10.dp),
                            ) {
                                Text(
                                    row.value,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = if (row.action is InfoRow.Action.Open || row.action is InfoRow.Action.Call) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                                    textDecoration = if (row.action is InfoRow.Action.Open) androidx.compose.ui.text.style.TextDecoration.Underline else null,
                                    maxLines = if (row.multiline) Int.MAX_VALUE else 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(row.title, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (index < state.rows.lastIndex) Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(0.5.dp).background(MaterialTheme.colorScheme.outlineVariant))
                        }
                    }
                }
            }
            if (onManage != null && (state.profile.kind == ChatProfile.Kind.GROUP || state.profile.kind == ChatProfile.Kind.CHANNEL)) {
                item(key = "manage") {
                    TextButton(onClick = onManage, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Управление") }
                }
            }
            if (state.commands.isNotEmpty()) {
                item(key = "commands") {
                    Card(title = "Команды") {
                        state.commands.forEach { command ->
                            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                                Text("/${command.name}", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
                                command.description?.takeIf { it.isNotBlank() }?.let {
                                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
            state.blocked?.let { blocked ->
                item(key = "block") {
                    Card {
                        Text(
                            if (blocked) "Разблокировать" else "Заблокировать",
                            Modifier.fillMaxWidth()
                                .clickable(enabled = !state.blocking) { if (blocked) model.toggleBlocked() else confirmingBlock = true }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            color = if (blocked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyLarge,
                        )
                    }
                }
            }
            state.error?.let { error ->
                item(key = "error") {
                    Text(error, Modifier.fillMaxWidth().padding(24.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.error)
                }
            }
            val tabs = state.shared.tabs
            if (tabs.isNotEmpty()) {
                item(key = "tabs") {
                    PrimaryScrollableTabRow(
                        selectedTabIndex = tabs.indexOf(state.tab).coerceAtLeast(0),
                        edgePadding = 12.dp,
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLowest,
                        modifier = Modifier.padding(top = 12.dp),
                    ) {
                        tabs.forEach { tab ->
                            Tab(
                                selected = tab == state.tab,
                                onClick = { model.selectTab(tab) },
                                text = { Text("${tab.title} ${state.shared.count(tab)}") },
                            )
                        }
                    }
                }
                when (state.tab) {
                    SharedMediaTab.MEDIA -> items(state.shared.media.chunked(3), key = { row -> "m-" + row.first().key }) { row ->
                        Row(Modifier.fillMaxWidth().padding(horizontal = 1.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            row.forEach { visual -> VisualTile(visual, Modifier.weight(1f)) { model.media.openVisual(visual.message, visual.attachment) } }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                        Spacer(Modifier.height(2.dp))
                    }
                    SharedMediaTab.FILES -> items(state.shared.files, key = { "f-" + it.key }) { file ->
                        val progress = mediaState.downloads[file.file.id]
                        ListRow(
                            leading = {
                                Box(Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
                                    if (progress != null) CircularProgressIndicator(progress = { progress }, Modifier.size(32.dp), color = MaterialTheme.colorScheme.onPrimary, strokeWidth = 2.dp)
                                    else Text(file.ext.ifEmpty { "FILE" }, color = MaterialTheme.colorScheme.onPrimary, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                            },
                            title = file.file.name,
                            subtitle = file.details,
                        ) { model.media.openFile(file.message, file.file) }
                    }
                    SharedMediaTab.LINKS -> items(state.shared.links, key = { "l-" + it.key }) { link ->
                        ListRow(
                            leading = {
                                Box(
                                    Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(AvatarPalette.nameColor(link.host.length)),
                                    contentAlignment = Alignment.Center,
                                ) { Text(link.letter, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 18.sp) }
                            },
                            title = link.host,
                            subtitle = link.context ?: link.url,
                            detail = link.url.takeIf { link.context != null },
                        ) { start(context, Intent(Intent.ACTION_VIEW, Uri.parse(link.url))) }
                    }
                    SharedMediaTab.VOICE -> items(state.shared.voices, key = { "v-" + it.key }) { voice ->
                        val playing = playback?.takeIf { it.matches(voice.message.id, voice.voice.id) }
                        ListRow(
                            leading = {
                                Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
                                    Icon(if (playing?.isPlaying == true) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, tint = MaterialTheme.colorScheme.onPrimary)
                                }
                            },
                            title = voice.author,
                            subtitle = voice.details,
                        ) { model.media.toggleVoice(voice.message, voice.voice) }
                    }
                }
                if (state.loadingShared) {
                    item(key = "more") {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) }
                    }
                }
            }
        }
    }

    mediaState.viewer?.let { viewer ->
        MediaViewer(viewer, mediaUserAgent, onPage = model.media::showPage, onClose = model.media::closeViewer)
    }
}

private fun start(context: android.content.Context, intent: Intent) {
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // Нечем открыть: действие просто не выполняется.
    }
}

@Composable
private fun Header(state: ProfileUiState) {
    Column(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // Кольцо историй собеседника: владельца вне ленты профиль спрашивает сам.
        val stories = app.orbitle.ui.stories.LocalStoryRings.current
        val ownerType = when (state.profile.kind) {
            app.orbitle.domain.ChatProfile.Kind.GROUP -> app.orbitle.domain.StoryOwner.Type.CHAT
            app.orbitle.domain.ChatProfile.Kind.CHANNEL -> app.orbitle.domain.StoryOwner.Type.CHANNEL
            else -> app.orbitle.domain.StoryOwner.Type.USER
        }
        val ownerId = when (state.profile.kind) {
            app.orbitle.domain.ChatProfile.Kind.USER, app.orbitle.domain.ChatProfile.Kind.BOT -> state.profile.peerId
            app.orbitle.domain.ChatProfile.Kind.GROUP, app.orbitle.domain.ChatProfile.Kind.CHANNEL -> state.profile.chatId
            else -> null
        }
        androidx.compose.runtime.LaunchedEffect(ownerId, ownerType) { stories.loadOwner(ownerId, ownerType) }
        app.orbitle.ui.stories.StoryRingAvatar(
            state.avatar,
            stories.ringFor(ownerId, ownerType),
            104.dp,
            onRingClick = ownerId?.let { id -> { stories.open(id) } },
        )
        Spacer(Modifier.height(14.dp))
        Row(Modifier.padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(state.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (state.profile.isOfficial) {
                Spacer(Modifier.width(6.dp))
                Icon(Icons.Filled.Verified, "Официальный", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(22.dp))
            }
        }
        if (state.subtitle.isNotEmpty()) {
            Spacer(Modifier.height(4.dp))
            Text(
                state.subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = if (state.subtitleAccent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (state.isLoading && state.rows.isEmpty()) {
            Spacer(Modifier.height(12.dp))
            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
        }
    }
}

@Composable
private fun ActionButton(label: String, icon: @Composable () -> Unit, modifier: Modifier, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.primary, modifier = modifier) {
        Column(Modifier.padding(vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            icon()
            Spacer(Modifier.height(4.dp))
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}

/** Плитка «Ещё»: участники и жалоба, очистка истории, удаление чата. */
@Composable
private fun MoreChatActions(actions: ProfileChatActions, modifier: Modifier, leavesGroup: Boolean = false) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        ActionButton("Ещё", { Icon(Icons.Outlined.MoreVert, null) }, Modifier.fillMaxWidth()) { open = true }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("Участники и жалоба") }, onClick = { open = false; actions.onTools() })
            val leave = actions.onLeave
            if (leavesGroup && leave != null) {
                DropdownMenuItem(text = { Text("Покинуть группу") }, onClick = { open = false; leave() })
            }
            DropdownMenuItem(text = { Text("Очистить историю") }, onClick = { open = false; actions.onClearHistory() })
            DropdownMenuItem(
                text = { Text("Удалить чат", color = MaterialTheme.colorScheme.error) },
                onClick = { open = false; actions.onDeleteChat() },
            )
        }
    }
}

@Composable
private fun Card(title: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
        title?.let { Text(it, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)) }
        Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceContainer) { Column { content() } }
    }
}

@Composable
private fun VisualTile(visual: SharedMedia.Visual, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.aspectRatio(1f).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onClick)) {
        AsyncImage(visual.thumbnailUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        if (visual.attachment is ChatAttachment.Video) {
            Row(
                Modifier.align(Alignment.BottomStart).padding(4.dp).clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 4.dp, vertical = 1.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(12.dp))
                visual.duration?.let { Text(it, color = Color.White, fontSize = 11.sp) }
            }
        }
    }
}

@Composable
private fun ListRow(leading: @Composable () -> Unit, title: String, subtitle: String, detail: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        leading()
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}
