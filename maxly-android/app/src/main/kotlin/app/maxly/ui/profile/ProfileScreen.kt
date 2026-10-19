package app.maxly.ui.profile

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
import androidx.compose.material.icons.outlined.Edit
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
import app.maxly.domain.ChatAttachment
import app.maxly.domain.ChatProfile
import app.maxly.domain.SharedMediaTab
import app.maxly.presentation.profile.InfoRow
import app.maxly.presentation.profile.ProfileUiState
import app.maxly.presentation.profile.ProfileViewModel
import app.maxly.presentation.profile.SharedMedia
import app.maxly.ui.chat.FileOpener
import app.maxly.ui.chat.MediaViewer
import app.maxly.ui.chat.mediaTile
import app.maxly.ui.components.Avatar
import app.maxly.ui.theme.AvatarPalette
import coil3.compose.AsyncImage
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.platform.LocalDensity
import app.maxly.presentation.media.ImageRequests
import app.maxly.presentation.media.AvatarPhoto
import androidx.compose.foundation.combinedClickable

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

    model.contactActions?.let { app.maxly.ui.contacts.ContactActionsHost(it, model::notify) }
    LaunchedEffect(notice) {
        val text = notice ?: return@LaunchedEffect
        // Поверх открытого просмотра снекбар не виден: «Фото сохранено» и ошибки — всплывающей подсказкой.
        if (text == AvatarPhoto.SAVED || mediaState.viewer != null) {
            model.consumeNotice()
            android.widget.Toast.makeText(context, text, android.widget.Toast.LENGTH_SHORT).show()
            return@LaunchedEffect
        }
        snackbar.showSnackbar(text)
        model.consumeNotice()
    }
    // До Android 10 запись в общие папки требует разрешения.
    val avatarStorage = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) model.media.saveAvatar() else model.notify("Нет доступа к памяти телефона") }
    val requestAvatarSave: () -> Unit = {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q ||
            androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
        ) model.media.saveAvatar() else avatarStorage.launch(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
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
                actions = {
                    // «Изменить» группу или канал, как в Max: карандаш у админа и владельца.
                    val editable = state.profile.kind == ChatProfile.Kind.GROUP || state.profile.kind == ChatProfile.Kind.CHANNEL
                    if (onManage != null && editable && state.profile.isAdmin) {
                        IconButton(onClick = onManage) { Icon(Icons.Outlined.Edit, "Изменить") }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest),
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = MaterialTheme.colorScheme.surfaceContainerLowest,
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = 24.dp)) {
            item(key = "header") {
                Header(state, photoId = model.avatarPhotoId, onPhoto = { preview -> model.openAvatar(preview) })
            }
            item(key = "actions") {
                if (chatActions != null) {
                    ProfileActionRow(
                        state = state,
                        actions = chatActions,
                        onWrite = onWrite,
                        onBack = onBack,
                        onShareLink = { link ->
                            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
                            start(context, Intent.createChooser(send, state.title))
                        },
                        onBlock = { if (state.blocked == true) model.toggleBlocked() else confirmingBlock = true },
                        onSendContact = model::shareContact,
                    )
                } else {
                    // Профиль участника: написать ему и поделиться ссылкой.
                    val share = state.profile.link
                    val canWrite = onWrite != null && state.profile.kind in setOf(ChatProfile.Kind.USER, ChatProfile.Kind.BOT, ChatProfile.Kind.SAVED)
                    if (canWrite || share != null) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            if (canWrite) ActionButton("Написать", { Icon(Icons.AutoMirrored.Outlined.Chat, null) }, Modifier.weight(1f)) { onWrite?.invoke() }
                            if (share != null) ActionButton("Поделиться", { Icon(Icons.Outlined.Share, null) }, Modifier.weight(1f)) {
                            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, share)
                            start(context, Intent.createChooser(send, state.title))
                            }
                        }
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
            if (state.contact != null && model.contactActions != null) {
                item(key = "contact") {
                    Card {
                        Text(
                            "Переименовать контакт",
                            Modifier.fillMaxWidth().clickable(onClick = model::askRenameContact).padding(horizontal = 16.dp, vertical = 14.dp),
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        Text(
                            "Удалить из контактов",
                            Modifier.fillMaxWidth().clickable(onClick = model::askRemoveContact).padding(horizontal = 16.dp, vertical = 14.dp),
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyLarge,
                        )
                    }
                }
            }
            state.blocked?.takeIf { chatActions == null }?.let { blocked ->
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
        if (AvatarPhoto.isAvatar(viewer)) {
            MediaViewer(
                viewer, mediaUserAgent, onPage = model.media::showPage, onClose = model.media::closeViewer,
                onSave = if (model.media.canSaveAvatar()) requestAvatarSave else null,
                saveLabel = "Сохранить в галерею",
                saving = viewer.messageId in mediaState.saving,
            )
        } else {
            MediaViewer(viewer, mediaUserAgent, onPage = model.media::showPage, onClose = model.media::closeViewer, onShare = model.media::shareViewed)
        }
    }
    app.maxly.ui.chat.ShareFileEffect(model.media)
}

private fun start(context: android.content.Context, intent: Intent) {
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // Нечем открыть: действие просто не выполняется.
    }
}

/**
 * Шапка профиля. Касание фото открывает его на весь экран ([onPhoto] получает квадрат шапки,
 * он виден, пока грузится оригинал). С кольцом историй касание открывает истории, а фото —
 * долгое нажатие. Без фото аватар не нажимается.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun Header(state: ProfileUiState, photoId: String?, onPhoto: (String?) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // Кольцо историй собеседника: владельца вне ленты профиль спрашивает сам.
        val stories = app.maxly.ui.stories.LocalStoryRings.current
        val ownerType = when (state.profile.kind) {
            app.maxly.domain.ChatProfile.Kind.GROUP -> app.maxly.domain.StoryOwner.Type.CHAT
            app.maxly.domain.ChatProfile.Kind.CHANNEL -> app.maxly.domain.StoryOwner.Type.CHANNEL
            else -> app.maxly.domain.StoryOwner.Type.USER
        }
        val ownerId = when (state.profile.kind) {
            app.maxly.domain.ChatProfile.Kind.USER, app.maxly.domain.ChatProfile.Kind.BOT -> state.profile.peerId
            app.maxly.domain.ChatProfile.Kind.GROUP, app.maxly.domain.ChatProfile.Kind.CHANNEL -> state.profile.chatId
            else -> null
        }
        androidx.compose.runtime.LaunchedEffect(ownerId, ownerType) { stories.loadOwner(ownerId, ownerType) }
        val ring = stories.ringFor(ownerId, ownerType)
        val size = 104.dp
        val density = LocalDensity.current
        val photoUrl = (state.avatar.kind as? app.maxly.presentation.chatlist.ChatAvatar.Kind.Photo)?.url?.takeIf { photoId != null }
        // Тот же адрес, что у картинки аватара: просмотр берёт её из кэша и вылетает с её места.
        val inner = if (ring == null) size else size - (size.value * 0.045f).coerceIn(2f, 3.5f).dp * 4
        val preview = photoUrl?.let { ImageRequests.square(it, inner.value, density.density) }
        val openStories = ownerId?.takeIf { ring != null }?.let { id -> { stories.open(id) } }
        val openPhoto = if (photoUrl != null) ({ onPhoto(preview) }) else null
        val tap = openStories ?: openPhoto
        val press = Modifier
            .then(if (photoId != null) Modifier.mediaTile(photoId, preview, with(density) { inner.toPx() } / 2) else Modifier)
            .then(
                if (tap != null) {
                    Modifier.clip(CircleShape).combinedClickable(
                        onClickLabel = if (openStories != null) "Открыть истории" else "Открыть фото",
                        onLongClickLabel = if (openStories != null && openPhoto != null) "Открыть фото" else null,
                        onLongClick = if (openStories != null) openPhoto else null,
                        onClick = tap,
                    )
                } else {
                    Modifier
                },
            )
        app.maxly.ui.stories.StoryRingAvatar(state.avatar, ring, size, modifier = press)
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

@Composable
private fun Card(title: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
        title?.let { Text(it, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)) }
        Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceContainer) { Column { content() } }
    }
}

@Composable
private fun VisualTile(visual: SharedMedia.Visual, modifier: Modifier, onClick: () -> Unit) {
    BoxWithConstraints(modifier.aspectRatio(1f).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onClick)) {
        val model = ImageRequests.width(visual.thumbnailUrl, maxWidth.value, LocalDensity.current.density)
        // Просмотр вылетает из клетки и возвращается в неё, как из плитки в ленте.
        androidx.compose.runtime.DisposableEffect(visual.attachment.id) { onDispose { app.maxly.ui.chat.MediaTiles.remove(visual.attachment.id) } }
        AsyncImage(model, null, Modifier.fillMaxSize().then(Modifier.mediaTile(visual.attachment.id, model, 0f)), contentScale = ContentScale.Crop)
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
