package app.maxly.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.automirrored.outlined.ExitToApp
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.CleaningServices
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import app.maxly.domain.ChatProfile
import app.maxly.domain.StoryOwner
import app.maxly.presentation.chatlist.ChatListItem
import app.maxly.presentation.chatlist.ChatListMenu
import app.maxly.presentation.profile.ProfileMenu
import app.maxly.presentation.profile.ProfileMenu.Entry
import app.maxly.presentation.profile.ProfileMenu.Tile
import app.maxly.presentation.profile.ProfileUiState
import app.maxly.ui.chatlist.CreateFolderDialog
import app.maxly.ui.chatlist.FolderSubmenu

/**
 * Действия чата, из которого открыт профиль: плитки под шапкой и «Ещё», как в Max
 * ([ProfileMenu]). Поиск, звонки, стирание и удаление закрывают профиль и открываются в чате
 * ([app.maxly.ui.chat.ChatAction]); звук, папки и карточка контакта работают на месте.
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
    val onVideoCall: () -> Unit = onCall,
    /** Уведомления чата выключены; `null` — неизвестно (плитки «Звук» нет). */
    val muted: Boolean? = null,
    val onMuteFor: (ChatListMenu.MuteFor) -> Unit = {},
    val onUnmute: () -> Unit = {},
    /** Папки для «Добавить в папку»; `null` — менять их нечем. */
    val folders: List<ChatListMenu.FolderChoice>? = null,
    val onToggleFolder: (String) -> Unit = {},
    val onCreateFolder: (String) -> Unit = {},
    /** Куда можно отправить карточку контакта. */
    val shareTargets: () -> List<ChatListItem> = { emptyList() },
)

/** Подменю «Ещё». */
private enum class MorePage { MAIN, FOLDERS }

/**
 * Ряд плиток профиля: [onWrite] открывает переписку (у профиля открытого чата — [onBack]),
 * [onShareLink] — ссылка группы или канала, [onBlock] — «Заблокировать» (с подтверждением) или
 * «Разблокировать», [onSendContact] — карточка собеседника в другой чат.
 */
@Composable
fun ProfileActionRow(
    state: ProfileUiState,
    actions: ProfileChatActions,
    onWrite: (() -> Unit)?,
    onBack: () -> Unit,
    onShareLink: (String) -> Unit,
    onBlock: () -> Unit,
    /** Отправить карточку собеседника в выбранный чат. */
    onSendContact: (targetChatId: String) -> Unit,
) {
    val profile = state.profile
    val listed = actions.onJoin == null
    val tiles = ProfileMenu.tiles(profile, listed).filterNot { it == Tile.SOUND && actions.muted == null }
    val stories = app.maxly.ui.stories.LocalStoryRings.current
    val owner = storyOwner(profile)
    val ring = owner?.let { stories.ringFor(it.id, it.type) }
    val hasStories = ring != null && stories.state.own?.owner?.id != ring.owner.id
    val entries = ProfileMenu.entries(profile, tiles, listed, actions.folders, hasStories, state.blocked)
    var sharing by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        tiles.forEach { tile ->
            val weight = Modifier.weight(1f)
            when (tile) {
                Tile.CHAT -> Tile(tile.title, Icons.AutoMirrored.Outlined.Chat, weight) { (onWrite ?: onBack)() }
                Tile.CALL -> Tile(tile.title, Icons.Outlined.Phone, weight) { actions.onCall() }
                Tile.VIDEO -> Tile(tile.title, Icons.Outlined.Videocam, weight) { actions.onVideoCall() }
                Tile.SOUND -> SoundTile(actions, weight)
                Tile.SEARCH -> Tile(tile.title, Icons.Outlined.Search, weight) { actions.onSearch() }
                Tile.JOIN, Tile.SUBSCRIBE -> Tile(tile.title, Icons.Outlined.AddCircle, weight) { actions.onJoin?.invoke() }
                Tile.MORE -> MoreTile(entries, weight, actions.onToggleFolder, actions.onCreateFolder) { entry ->
                    when (entry) {
                        Entry.ShareContact -> sharing = true
                        Entry.ShareLink -> profile.link?.let(onShareLink)
                        is Entry.Folders -> Unit
                        Entry.Search -> actions.onSearch()
                        Entry.Erase -> actions.onClearHistory()
                        Entry.HideStories -> if (owner != null) stories.hide(owner, ring?.name ?: state.title)
                        is Entry.Tools -> actions.onTools()
                        is Entry.Block -> onBlock()
                        is Entry.Leave -> actions.onLeave?.invoke()
                        is Entry.Delete -> actions.onDeleteChat()
                    }
                }
            }
        }
    }
    if (sharing) {
        app.maxly.ui.chat.ForwardPicker(
            targets = remember { actions.shareTargets() },
            onPick = { target -> sharing = false; onSendContact(target) },
            onDismiss = { sharing = false },
            title = "Поделиться контактом",
        )
    }
}

@Composable
private fun SoundTile(actions: ProfileChatActions, modifier: Modifier) {
    var open by remember { mutableStateOf(false) }
    val muted = actions.muted == true
    Box(modifier) {
        Tile("Звук", if (muted) Icons.Outlined.NotificationsOff else Icons.Outlined.Notifications, Modifier.fillMaxWidth()) {
            if (muted) actions.onUnmute() else open = true
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            ChatListMenu.MuteFor.entries.forEach { choice ->
                MenuItem(choice.title, null, danger = choice.isDanger) { open = false; actions.onMuteFor(choice) }
            }
        }
    }
}

@Composable
private fun MoreTile(
    entries: List<Entry>,
    modifier: Modifier,
    onToggleFolder: (String) -> Unit,
    onCreateFolder: (String) -> Unit,
    onEntry: (Entry) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    var page by remember { mutableStateOf(MorePage.MAIN) }
    var creating by remember { mutableStateOf(false) }
    val folders = entries.firstNotNullOfOrNull { it as? Entry.Folders }
    val close = { open = false; page = MorePage.MAIN }
    Box(modifier) {
        Tile(Tile.MORE.title, Icons.Outlined.MoreHoriz, Modifier.fillMaxWidth()) { open = true }
        DropdownMenu(expanded = open, onDismissRequest = close) {
            when (page) {
                MorePage.MAIN -> entries.forEach { entry ->
                    MenuItem(entry.title, icon(entry), danger = entry.isDanger, more = entry is Entry.Folders) {
                        if (entry is Entry.Folders) {
                            page = MorePage.FOLDERS
                        } else {
                            close()
                            onEntry(entry)
                        }
                    }
                }
                MorePage.FOLDERS -> FolderSubmenu(
                    folders = folders?.folders.orEmpty(),
                    onBack = { page = MorePage.MAIN },
                    onToggle = { id -> close(); onToggleFolder(id) },
                    onCreate = { close(); creating = true },
                )
            }
        }
    }
    if (creating) {
        CreateFolderDialog(onCreate = { title -> creating = false; onCreateFolder(title) }, onDismiss = { creating = false })
    }
}

@Composable
private fun Tile(label: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.primary, modifier = modifier) {
        Column(Modifier.padding(vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null)
            Spacer(Modifier.height(4.dp))
            Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1)
        }
    }
}

@Composable
private fun MenuItem(title: String, icon: ImageVector?, danger: Boolean = false, more: Boolean = false, onClick: () -> Unit) {
    val error = MaterialTheme.colorScheme.error
    DropdownMenuItem(
        text = { Text(title) },
        leadingIcon = icon?.let { { Icon(it, null) } },
        trailingIcon = if (more) ({ Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) }) else null,
        colors = if (danger) MenuDefaults.itemColors(textColor = error, leadingIconColor = error) else MenuDefaults.itemColors(),
        onClick = onClick,
    )
}

private fun icon(entry: Entry): ImageVector = when (entry) {
    Entry.ShareContact -> Icons.Outlined.Share
    Entry.ShareLink -> Icons.Outlined.Link
    is Entry.Folders -> Icons.Outlined.CreateNewFolder
    Entry.Search -> Icons.Outlined.Search
    Entry.Erase -> Icons.Outlined.CleaningServices
    Entry.HideStories -> Icons.Outlined.VisibilityOff
    is Entry.Tools -> Icons.Outlined.Flag
    is Entry.Block -> Icons.Outlined.Block
    is Entry.Leave -> Icons.AutoMirrored.Outlined.ExitToApp
    is Entry.Delete -> Icons.Outlined.Delete
}

/** Владелец историй профиля: человек, группа или канал. */
private fun storyOwner(profile: ChatProfile): StoryOwner? = when (profile.kind) {
    ChatProfile.Kind.USER -> profile.peerId?.let { StoryOwner(it, StoryOwner.Type.USER) }
    ChatProfile.Kind.GROUP -> StoryOwner(profile.chatId, StoryOwner.Type.CHAT)
    ChatProfile.Kind.CHANNEL -> StoryOwner(profile.chatId, StoryOwner.Type.CHANNEL)
    else -> null
}
