package app.orbitle.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.AppContainer
import app.orbitle.R
import app.orbitle.data.PrivateModeSettings
import app.orbitle.domain.Account
import app.orbitle.domain.Chat
import app.orbitle.platform.BackHandler
import app.orbitle.presentation.calls.CallsViewModel
import app.orbitle.presentation.chat.ChatViewModel
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.presentation.chatlist.NewChatModel
import app.orbitle.presentation.contacts.ContactsViewModel
import app.orbitle.presentation.profile.ProfileViewModel
import app.orbitle.presentation.settings.AccountSettingsViewModel
import app.orbitle.presentation.settings.FoldersViewModel
import app.orbitle.presentation.settings.ProfileLink
import app.orbitle.domain.MiniApp
import app.orbitle.presentation.settings.MiniAppViewModel
import app.orbitle.presentation.settings.RecoveryEmailViewModel
import app.orbitle.presentation.settings.SecurityViewModel
import app.orbitle.presentation.settings.StorageViewModel
import app.orbitle.ui.calls.CallsScreen
import app.orbitle.ui.chat.ChatAction
import app.orbitle.ui.chat.ChatScreen
import app.orbitle.ui.chat.EmojiSupport
import app.orbitle.ui.chatlist.ChatListScreen
import app.orbitle.ui.components.LocalPrivateMode
import app.orbitle.ui.contacts.ContactsScreen
import app.orbitle.ui.profile.ProfileChatActions
import app.orbitle.ui.profile.ProfileScreen
import app.orbitle.ui.res.stringResource
import app.orbitle.ui.settings.AboutScreen
import app.orbitle.ui.settings.AppearanceScreen
import app.orbitle.ui.settings.BlockedUsersScreen
import app.orbitle.ui.settings.DevicesScreen
import app.orbitle.ui.settings.FoldersScreen
import app.orbitle.ui.settings.MessagesScreen
import app.orbitle.ui.settings.MiniAppScreen
import app.orbitle.ui.settings.PrivacyScreen
import app.orbitle.ui.settings.ProfileEditScreen
import app.orbitle.ui.settings.RecoveryEmailScreen
import app.orbitle.ui.settings.SecurityScreen
import app.orbitle.ui.settings.SettingsScreen
import app.orbitle.ui.settings.StorageScreen

/** Вкладки боковой панели. */
enum class Tab(val title: Int, val icon: ImageVector, val selectedIcon: ImageVector) {
    CHATS(R.string.tab_chats, Icons.Outlined.ChatBubbleOutline, Icons.AutoMirrored.Filled.Chat),
    CALLS(R.string.tab_calls, Icons.Outlined.Call, Icons.Filled.Call),
    CONTACTS(R.string.tab_contacts, Icons.Outlined.Person, Icons.Filled.Person),
    SETTINGS(R.string.tab_settings, Icons.Outlined.Settings, Icons.Filled.Settings),
}

private enum class SettingsPage { Home, About, Devices, Appearance, Profile, Privacy, Security, RecoveryEmail, Storage, Folders, Blocked, MiniApp, Messages }

/** Окно после входа: рельс вкладок, список чатов и открытый чат рядом. */
@Composable
fun MainScreen(
    container: AppContainer,
    chatList: ChatListViewModel,
    account: Account?,
    onLogout: () -> Unit,
) {
    var tab by rememberSaveable { mutableStateOf(Tab.CHATS) }
    var chatId by rememberSaveable { mutableStateOf<String?>(null) }
    var chatTitle by rememberSaveable { mutableStateOf<String?>(null) }
    var profileFor by rememberSaveable { mutableStateOf<String?>(null) }
    var settingsPage by rememberSaveable { mutableStateOf(SettingsPage.Home) }
    var recoveryKey by rememberSaveable { mutableIntStateOf(0) }
    var miniAppKey by rememberSaveable { mutableIntStateOf(0) }
    var miniKind by rememberSaveable { mutableStateOf(MiniApp.Kind.DIGITAL_ID.wire) }
    val chats by chatList.state.collectAsStateWithLifecycle()
    val callsModel = viewModel { CallsViewModel(container.calls, container.callMarks) }
    val calls by callsModel.state.collectAsStateWithLifecycle()
    val accountModel = viewModel { AccountSettingsViewModel(container.account) }
    val accountState by accountModel.state.collectAsStateWithLifecycle()
    val contactsModel = viewModel { ContactsViewModel(container.contacts, { container.messages.currentUserId }, chats = container.chats) }
    val newChat = viewModel(key = "new-chat") { NewChatModel(container.contacts, container.chats) { container.messages.currentUserId } }
    val privatePrefs by container.privateMode.state.collectAsStateWithLifecycle()
    val privateDisplay = PrivateModeSettings.display(privatePrefs, canBlur = true)
    fun openChat(id: String, title: String? = null) {
        chatId = id
        chatTitle = title
        profileFor = null
        tab = Tab.CHATS
    }
    BackHandler(enabled = tab == Tab.SETTINGS && settingsPage != SettingsPage.Home) {
        settingsPage = when (settingsPage) {
            SettingsPage.Blocked -> SettingsPage.Privacy
            SettingsPage.RecoveryEmail -> SettingsPage.Security
            else -> SettingsPage.Home
        }
    }
    BackHandler(enabled = tab == Tab.CHATS && profileFor != null) { profileFor = null }
    BackHandler(enabled = tab == Tab.CHATS && profileFor == null && chatId != null) {
        chatId = null
        chatTitle = null
    }
    CompositionLocalProvider(LocalPrivateMode provides privateDisplay) {
        Row(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            NavigationRail {
                Tab.entries.forEach { item ->
                    val selected = tab == item
                    NavigationRailItem(
                        selected = selected,
                        onClick = { tab = item },
                        icon = {
                            BadgedBox(badge = {
                                if (item == Tab.CHATS && chats.tabBadge > 0) Badge { Text(ChatListFormatter.compactCount(chats.tabBadge)) }
                                if (item == Tab.CALLS && calls.unseenMissed > 0) Badge { Text(ChatListFormatter.compactCount(calls.unseenMissed)) }
                            }) {
                                Icon(if (selected) item.selectedIcon else item.icon, contentDescription = stringResource(item.title))
                            }
                        },
                        label = { Text(stringResource(item.title)) },
                    )
                }
            }
            when (tab) {
                Tab.CHATS -> Row(Modifier.weight(1f).fillMaxHeight()) {
                    Box(Modifier.width(360.dp).fillMaxHeight()) {
                        ChatListScreen(
                            chatList,
                            onOpenChat = { openChat(it.id) },
                            onOpenFound = { openChat(it.id, it.title) },
                            onOpenMessage = { openChat(it.chatId) },
                            privateMode = privatePrefs,
                            onTogglePrivateMode = container.privateMode::toggle,
                            newChat = newChat,
                            onOpenCreated = { id, title -> openChat(id, title) },
                        )
                    }
                    VerticalDivider()
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        ChatPane(
                            container = container,
                            chatList = chatList,
                            chatId = chatId,
                            chatTitle = chatTitle,
                            profileFor = profileFor,
                            onOpenProfile = { profileFor = chatId },
                            onCloseProfile = { profileFor = null },
                            onCloseChat = {
                                chatId = null
                                chatTitle = null
                            },
                            quickReaction = accountState.settings.quickReaction.takeIf { accountState.settings.quickReactionEnabled },
                        )
                    }
                }
                Tab.CALLS -> Box(Modifier.weight(1f).fillMaxHeight()) {
                    CallsScreen(callsModel, onOpenChat = { openChat(it) })
                }
                Tab.CONTACTS -> Box(Modifier.weight(1f).fillMaxHeight()) {
                    ContactsScreen(contactsModel, onOpen = { row -> contactsModel.prepare(row.id, row.title)?.let { openChat(it, row.title) } })
                }
                Tab.SETTINGS -> Box(Modifier.weight(1f).fillMaxHeight()) {
                    SettingsPane(
                        container = container,
                        chatList = chatList,
                        account = account,
                        accountModel = accountModel,
                        profileLink = ProfileLink.link(accountState.settings.inviteLink, account?.link),
                        page = settingsPage,
                        onOpen = { settingsPage = it },
                        onBack = {
                            settingsPage = when (settingsPage) {
                                SettingsPage.Blocked -> SettingsPage.Privacy
                                SettingsPage.RecoveryEmail -> SettingsPage.Security
                                else -> SettingsPage.Home
                            }
                        },
                        recoveryKey = recoveryKey,
                        onOpenRecovery = {
                            recoveryKey += 1
                            settingsPage = SettingsPage.RecoveryEmail
                        },
                        miniAppKey = miniAppKey,
                        miniKind = miniKind,
                        onOpenMiniApp = { kind ->
                            miniKind = kind.wire
                            miniAppKey += 1
                            settingsPage = SettingsPage.MiniApp
                        },
                        onLogout = onLogout,
                        onSaved = { openChat(Chat.SAVED_MESSAGES_ID) },
                        onContacts = { tab = Tab.CONTACTS },
                    )
                }
            }
        }
    }
}

@Composable
private fun ChatPane(
    container: AppContainer,
    chatList: ChatListViewModel,
    chatId: String?,
    chatTitle: String?,
    profileFor: String?,
    onOpenProfile: () -> Unit,
    onCloseProfile: () -> Unit,
    onCloseChat: () -> Unit,
    quickReaction: String? = null,
) {
    // Действие из профиля (поиск, «О чате», звонок, очистка, удаление): чат откроет его после возврата.
    var chatAction by remember { mutableStateOf<Pair<String, ChatAction>?>(null) }
    when {
        chatId == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                "Выберите чат",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        profileFor != null -> {
            val model = viewModel(key = "profile-$profileFor") {
                ProfileViewModel(profileFor, chatTitle, container.profiles, container.messages, container.voicePlayer, container.files)
            }
            ProfileScreen(
                model,
                onBack = onCloseProfile,
                onWrite = null,
                mediaUserAgent = container.videoSourceUserAgent(),
                chatActions = profileChatActions(listed = chatList.isListed(chatId)) { action ->
                    chatAction = chatId to action
                    onCloseProfile()
                },
            )
        }
        else -> {
            val model = viewModel(key = "chat-$chatId") {
                ChatViewModel(
                    chatId, container.messages, fallbackTitle = chatTitle, voicePlayer = container.voicePlayer, files = container.files,
                    stickerRepository = container.stickers, stickerRecents = container.stickerRecents, drafts = container.drafts,
                    emojiSupported = EmojiSupport::canDraw, comments = container.comments,
                    mediaSaver = container.mediaSaver,
                    chats = container.chats,
                    profiles = container.profiles,
                )
            }
            ChatScreen(
                model,
                onBack = onCloseChat,
                onOpenProfile = onOpenProfile,
                mediaUserAgent = container.videoSourceUserAgent(),
                forwardTargets = { chatList.forwardTargets(excluding = chatId) },
                onDisablePrivateMode = { container.privateMode.setEnabled(false) },
                quickReaction = quickReaction,
                requestedAction = chatAction?.takeIf { it.first == chatId }?.second,
                onActionHandled = { chatAction = null },
                botApp = { request, onClose ->
                    val app = viewModel(key = "bot-app-${request.botId}-${request.startParam}-${request.title}") {
                        MiniAppViewModel(null, container.account, request.title) {
                            container.account.launchBotApp(request.botId, request.chatId, request.startParam)
                        }
                    }
                    MiniAppScreen(app, onClose)
                },
            )
        }
    }
}

/** Действия профиля, открытого из чата: каждое закрывает профиль и открывается в чате. */
private fun profileChatActions(listed: Boolean = true, request: (ChatAction) -> Unit) = ProfileChatActions(
    onSearch = { request(ChatAction.SEARCH) },
    onTools = { request(ChatAction.TOOLS) },
    onCall = { request(ChatAction.CALL) },
    onClearHistory = { request(ChatAction.CLEAR_HISTORY) },
    onDeleteChat = { request(ChatAction.DELETE_CHAT) },
    onLeave = if (listed) ({ request(ChatAction.LEAVE) }) else null,
)

@Composable
private fun SettingsPane(
    container: AppContainer,
    chatList: ChatListViewModel,
    account: Account?,
    accountModel: AccountSettingsViewModel,
    profileLink: String?,
    page: SettingsPage,
    onOpen: (SettingsPage) -> Unit,
    onBack: () -> Unit,
    onLogout: () -> Unit,
    onSaved: () -> Unit,
    onContacts: () -> Unit,
    recoveryKey: Int,
    onOpenRecovery: () -> Unit,
    miniAppKey: Int,
    miniKind: String,
    onOpenMiniApp: (MiniApp.Kind) -> Unit,
) {
    val securityModel = viewModel { SecurityViewModel(container.account) }
    val limits by container.accountLimits.state.collectAsStateWithLifecycle()
    when (page) {
        SettingsPage.Home -> SettingsScreen(
            account,
            onAbout = { onOpen(SettingsPage.About) },
            onLogout = onLogout,
            onSaved = onSaved,
            onContacts = onContacts,
            onDevices = { onOpen(SettingsPage.Devices) },
            onAppearance = { onOpen(SettingsPage.Appearance) },
            onEditProfile = { onOpen(SettingsPage.Profile) },
            onPrivacy = { onOpen(SettingsPage.Privacy) },
            onSecurity = { onOpen(SettingsPage.Security) },
            onDigitalId = { onOpenMiniApp(MiniApp.Kind.DIGITAL_ID) },
            onSferum = { onOpenMiniApp(MiniApp.Kind.SFERUM) },
            onStorage = { onOpen(SettingsPage.Storage) },
            onFolders = { onOpen(SettingsPage.Folders) },
            onMessages = { onOpen(SettingsPage.Messages) },
            profileLink = profileLink,
            accountLimits = limits,
        )
        SettingsPage.Messages -> MessagesScreen(
            accountModel,
            loadCatalog = { container.messages.reactionCatalog() },
            onBack = onBack,
        )
        SettingsPage.About -> AboutScreen(onBack)
        SettingsPage.Devices -> DevicesScreen(container.sessions, onBack)
        SettingsPage.Appearance -> AppearanceScreen(container.appearance, onBack)
        SettingsPage.Profile -> ProfileEditScreen(accountModel, onBack, onLogout)
        SettingsPage.Privacy -> PrivacyScreen(accountModel, onBack, onBlocked = { onOpen(SettingsPage.Blocked) }, privateMode = container.privateMode)
        SettingsPage.Security -> SecurityScreen(securityModel, onBack, onChangeEmail = onOpenRecovery)
        SettingsPage.RecoveryEmail -> {
            val flow = viewModel(key = "recovery-$recoveryKey") { RecoveryEmailViewModel(container.account) }
            RecoveryEmailScreen(
                flow,
                onBack = onBack,
                onDone = { status ->
                    securityModel.apply(status)
                    onOpen(SettingsPage.Security)
                },
            )
        }
        SettingsPage.Storage -> StorageScreen(viewModel { StorageViewModel(container.storage) }, onBack)
        SettingsPage.Folders -> FoldersScreen(
            viewModel { FoldersViewModel(container.folders) },
            count = chatList::folderCount,
            candidates = chatList::folderCandidates,
            onBack = onBack,
        )
        SettingsPage.Blocked -> BlockedUsersScreen(accountModel, onBack)
        SettingsPage.MiniApp -> {
            val kind = MiniApp.Kind.fromWire(miniKind) ?: MiniApp.Kind.DIGITAL_ID
            val miniModel = viewModel(key = "mini-$miniAppKey") { MiniAppViewModel(kind, container.account) }
            MiniAppScreen(miniModel, onBack)
        }
    }
}
