package app.maxly.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.foundation.layout.size
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
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import app.maxly.domain.OutgoingFile
import app.maxly.domain.OutgoingStory
import app.maxly.media.AttachmentImporter
import app.maxly.platform.DesktopActions
import app.maxly.presentation.stories.StoriesViewModel
import app.maxly.presentation.stories.StoryText
import app.maxly.ui.stories.LocalStoryRings
import app.maxly.ui.stories.StoriesStrip
import app.maxly.ui.stories.StoryStack
import app.maxly.ui.stories.StoryComposer
import app.maxly.ui.stories.StoryRings
import app.maxly.ui.stories.StoryViewer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.maxly.AppContainer
import app.maxly.R
import app.maxly.data.PrivateModeSettings
import app.maxly.domain.Account
import app.maxly.domain.Chat
import app.maxly.ui.keys.HotkeyAction
import app.maxly.ui.keys.HotkeyHandler
import app.maxly.ui.keys.LocalSendKey
import app.maxly.ui.settings.KeyboardScreen
import app.maxly.platform.BackHandler
import app.maxly.presentation.calls.CallsViewModel
import app.maxly.presentation.chat.BotAppRequest
import app.maxly.presentation.chat.ChatViewModel
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.presentation.chatlist.ChatListViewModel
import app.maxly.presentation.chatlist.NewChatModel
import app.maxly.presentation.contacts.ContactsViewModel
import app.maxly.presentation.profile.ProfileViewModel
import app.maxly.presentation.settings.AccountSettingsViewModel
import app.maxly.presentation.settings.FoldersViewModel
import app.maxly.presentation.settings.ProfileLink
import app.maxly.domain.MiniApp
import app.maxly.presentation.settings.MiniAppViewModel
import app.maxly.presentation.settings.RecoveryEmailViewModel
import app.maxly.presentation.settings.GhostModeViewModel
import app.maxly.presentation.settings.SecurityViewModel
import app.maxly.presentation.settings.StorageViewModel
import app.maxly.ui.calls.CallsScreen
import app.maxly.ui.chat.ChatAction
import app.maxly.ui.chat.ChatScreen
import app.maxly.ui.chat.EmojiSupport
import app.maxly.ui.chatlist.ChatListScreen
import app.maxly.ui.components.LocalPrivateMode
import app.maxly.ui.contacts.ContactsScreen
import app.maxly.ui.profile.ProfileChatActions
import app.maxly.ui.profile.ProfileScreen
import app.maxly.ui.res.stringResource
import app.maxly.ui.settings.AboutScreen
import app.maxly.ui.settings.AppearanceScreen
import app.maxly.ui.settings.BlockedUsersScreen
import app.maxly.ui.settings.DevicesScreen
import app.maxly.ui.settings.FoldersScreen
import app.maxly.ui.settings.MessagesScreen
import app.maxly.ui.settings.MiniAppScreen
import app.maxly.ui.settings.PrivacyScreen
import app.maxly.ui.settings.ProfileEditScreen
import app.maxly.ui.settings.RecoveryEmailScreen
import app.maxly.ui.settings.SecurityScreen
import app.maxly.ui.settings.SettingsScreen
import app.maxly.ui.settings.StorageScreen

/** Вкладки боковой панели. */
enum class Tab(val title: Int, val icon: ImageVector, val selectedIcon: ImageVector) {
    CHATS(R.string.tab_chats, Icons.Outlined.ChatBubbleOutline, Icons.AutoMirrored.Filled.Chat),
    CALLS(R.string.tab_calls, Icons.Outlined.Call, Icons.Filled.Call),
    CONTACTS(R.string.tab_contacts, Icons.Outlined.Person, Icons.Filled.Person),
    SETTINGS(R.string.tab_settings, Icons.Outlined.Settings, Icons.Filled.Settings),
}

private enum class SettingsPage { Home, About, Devices, Appearance, Profile, Privacy, Security, RecoveryEmail, Storage, Folders, Blocked, MiniApp, Messages, Keyboard, MyStories }

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
    val callsModel = viewModel { CallsViewModel(container.calls, container.callMarks, connection = container.session.connection) }
    val calls by callsModel.state.collectAsStateWithLifecycle()
    val accountModel = viewModel { AccountSettingsViewModel(container.account) }
    val accountState by accountModel.state.collectAsStateWithLifecycle()
    val contactsModel = viewModel { ContactsViewModel(container.contacts, { container.messages.currentUserId }, chats = container.chats) }
    val newChat = viewModel(key = "new-chat") { NewChatModel(container.contacts, container.chats) { container.messages.currentUserId } }
    val privatePrefs by container.privateMode.state.collectAsStateWithLifecycle()
    val sendKey by container.keyboard.sendKey.collectAsStateWithLifecycle()
    val privateDisplay = PrivateModeSettings.display(privatePrefs, canBlur = true)
    // Истории: одна модель на список, шапку чата и профиль.
    val storiesModel = viewModel { StoriesViewModel(container.stories, container.session.connection) }
    val stories by storiesModel.state.collectAsStateWithLifecycle()
    var composingStory by remember { mutableStateOf<OutgoingStory?>(null) }
    var listBotApp by remember { mutableStateOf<BotAppRequest?>(null) }
    val storyScope = rememberCoroutineScope()
    val storySnack = remember { SnackbarHostState() }
    val addStory = app.maxly.platform.rememberDesktopFilePicker(
        title = "Фото или видео для истории",
        media = true,
    ) { files ->
        val file = files.firstOrNull() ?: return@rememberDesktopFilePicker
        storyScope.launch {
            val picked = AttachmentImporter.import(listOf(file)).firstOrNull()
            composingStory = when (picked?.kind) {
                OutgoingFile.Kind.PHOTO -> OutgoingStory(picked.path, isVideo = false)
                OutgoingFile.Kind.VIDEO -> OutgoingStory(picked.path, isVideo = true)
                else -> null
            }
            if (composingStory == null) storySnack.showSnackbar("Не удалось открыть файл")
        }
    }
    LaunchedEffect(stories.message) {
        val text = stories.message ?: return@LaunchedEffect
        storiesModel.consumeMessage()
        storySnack.showSnackbar(text)
    }
    // Найденное в общем поиске сообщение: чат откроется на нём (id чата, id сообщения, время).
    var openMessage by remember { mutableStateOf<Triple<String, String, Long>?>(null) }
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
    // Горячие клавиши окна: поиск, соседний чат, папки, «Избранное»,
    // новое сообщение и настройки. Открытый чат и просмотр фото кладут свои поверх.
    HotkeyHandler { hotkey ->
        when (hotkey.action) {
            HotkeyAction.SEARCH, HotkeyAction.SEARCH_CHATS -> {
                tab = Tab.CHATS
                chatList.setSearchActive(true)
                true
            }
            HotkeyAction.NEXT_CHAT, HotkeyAction.PREVIOUS_CHAT -> {
                val list = chats.pages.firstOrNull { it.id == chats.selectedFolderId }?.items ?: chats.items
                if (list.isEmpty()) return@HotkeyHandler false
                val index = list.indexOfFirst { it.id == chatId }
                val next = when {
                    index < 0 -> 0
                    hotkey.action == HotkeyAction.NEXT_CHAT -> (index + 1).coerceAtMost(list.lastIndex)
                    else -> (index - 1).coerceAtLeast(0)
                }
                chatList.opened(list[next].id)
                openChat(list[next].id)
                true
            }
            HotkeyAction.FOLDER -> {
                val folder = chats.folders.getOrNull(hotkey.index) ?: return@HotkeyHandler false
                tab = Tab.CHATS
                chatList.setSearchActive(false)
                chatList.selectFolder(folder.id)
                true
            }
            HotkeyAction.SAVED_MESSAGES -> {
                openChat(Chat.SAVED_MESSAGES_ID)
                true
            }
            HotkeyAction.NEW_MESSAGE -> {
                tab = Tab.CHATS
                newChat.show()
                true
            }
            HotkeyAction.SETTINGS -> {
                tab = Tab.SETTINGS
                settingsPage = SettingsPage.Home
                true
            }
            else -> false
        }
    }
    BackHandler(enabled = tab == Tab.CHATS && profileFor != null) { profileFor = null }
    BackHandler(enabled = tab == Tab.CHATS && profileFor == null && chatId != null) {
        chatId = null
        chatTitle = null
    }
    CompositionLocalProvider(
        LocalPrivateMode provides privateDisplay,
        LocalStoryRings provides StoryRings(stories, storiesModel::open, storiesModel::loadRing, storiesModel::loadOwner),
        LocalSendKey provides sendKey,
    ) {
        Box(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
        val expanded = maxWidth >= 900.dp
        Row(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            NavigationRail(
                containerColor = MaterialTheme.colorScheme.surfaceContainer,
                header = {
                    // Кнопка размером с пункт панели: большая FAB на компьютере выглядит чужой.
                    androidx.compose.material3.SmallFloatingActionButton(
                        onClick = {
                            tab = Tab.CHATS
                            newChat.show()
                        },
                        modifier = Modifier.padding(vertical = 8.dp),
                        elevation = androidx.compose.material3.FloatingActionButtonDefaults.bottomAppBarFabElevation(),
                    ) {
                        Icon(Icons.Filled.Edit, contentDescription = "Новое сообщение (Ctrl+N)", modifier = Modifier.size(20.dp))
                    }
                },
            ) {
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
                    val showList = expanded || chatId == null
                    val showChat = expanded || chatId != null
                    if (showList) {
                    Box(Modifier.then(if (expanded) Modifier.width(360.dp) else Modifier.weight(1f)).fillMaxHeight()) {
                        val selfAvatar = StoryText.avatar(account?.id ?: container.messages.currentUserId.orEmpty(), account?.displayName.orEmpty(), account?.avatarUrl)
                        val stackItems = listOfNotNull(stories.own?.let { selfAvatar to it }) + stories.rings.map { StoryText.avatar(it) to it }
                        ChatListScreen(
                            chatList,
                            onOpenChat = { openChat(it.id) },
                            onOpenApp = { item ->
                                val botId = item.peerId
                                if (botId != null) listBotApp = BotAppRequest(botId, item.id, null, item.title)
                            },
                            onOpenFound = { openChat(it.id, it.title) },
                            onOpenMessage = {
                                openChat(it.chatId)
                                openMessage = Triple(it.chatId, it.messageId, it.timeMs)
                            },
                            privateMode = privatePrefs,
                            onTogglePrivateMode = container.privateMode::toggle,
                            newChat = newChat,
                            onOpenCreated = { id, title -> openChat(id, title) },
                            storiesHeader = {
                                StoriesStrip(
                                    stories,
                                    self = selfAvatar,
                                    onOpen = storiesModel::open,
                                    onAdd = addStory,
                                    onArchive = if (accountState.settings.storiesHistory) ({
                                        tab = Tab.SETTINGS
                                        settingsPage = SettingsPage.MyStories
                                    }) else null,
                                )
                            },
                            storyStack = if (stackItems.isEmpty()) null else ({ StoryStack(stackItems) }),
                            onAddStory = addStory,
                            onRetryLogin = { container.scope.launch { container.session.retryLogin() } },
                            onLogout = onLogout,
                        )
                    }
                    if (expanded) VerticalDivider()
                    }
                    if (showChat) {
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
                            openMessage = openMessage?.takeIf { it.first == chatId }?.let { it.second to it.third },
                            onMessageOpened = { openMessage = null },
                        )
                    }
                    }
                }
                Tab.CALLS -> Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                    Box(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight()) {
                    CallsScreen(
                        callsModel,
                        onOpenChat = { openChat(it) },
                        onJoin = { link -> container.scope.launch { container.callCenter.join(link) } },
                        onCall = { row, video ->
                            val peer = app.maxly.presentation.calls.CallPeerInfo(row.peerId, row.name, row.avatarUrl)
                            container.scope.launch { container.callCenter.startCall(peer, video) }
                        },
                    )
                    }
                }
                Tab.CONTACTS -> Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                    Box(Modifier.widthIn(max = 720.dp).fillMaxWidth().fillMaxHeight()) {
                    ContactsScreen(contactsModel, onOpen = { row -> contactsModel.prepare(row.id, row.title)?.let { openChat(it, row.title) } })
                    }
                }
                Tab.SETTINGS -> Box(Modifier.weight(1f).fillMaxHeight()) {
                    SettingsPane(
                        expanded = expanded,
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
                        onAddStory = addStory,
                        onFamilyProtection = { botId -> listBotApp = BotAppRequest(botId, "", null, "Семейная защита") },
                    )
                }
            }
        }
        }
        SnackbarHost(storySnack, Modifier.align(Alignment.BottomCenter))
        }
        stories.viewer?.let { viewer ->
            StoryViewer(
                viewer,
                userAgent = container.videoSourceUserAgent(),
                onNext = storiesModel::next,
                onPrevious = storiesModel::previous,
                onNextOwner = storiesModel::nextOwner,
                onPreviousOwner = storiesModel::previousOwner,
                onClose = storiesModel::close,
                onDelete = storiesModel::deleteCurrent,
            )
        }
        listBotApp?.let { request ->
            BackHandler { listBotApp = null }
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
                val app = viewModel(key = "list-bot-app-${request.botId}-${request.chatId}") {
                    MiniAppViewModel(null, container.account, request.title) {
                        container.account.launchBotApp(request.botId, request.chatId, request.startParam)
                    }
                }
                MiniAppScreen(app) { listBotApp = null }
            }
        }
        composingStory?.let { story ->
            StoryComposer(
                story,
                userAgent = container.videoSourceUserAgent(),
                onPublish = { audience ->
                    composingStory = null
                    storiesModel.publish(story, audience)
                },
                onCancel = { composingStory = null },
            )
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
    openMessage: Pair<String, Long>? = null,
    onMessageOpened: () -> Unit = {},
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
            var managing by remember { mutableStateOf(false) }
            var channel by remember { mutableStateOf(false) }
            if (managing) {
                val manage = viewModel(key = "manage-$profileFor-$channel") {
                    app.maxly.presentation.profile.ChatManageViewModel(
                        profileFor,
                        channel,
                        container.messages.currentUserId,
                        container.chatAdmin,
                    )
                }
                val people by container.contacts.contacts.collectAsStateWithLifecycle(initialValue = emptyList())
                app.maxly.ui.profile.ManageRoute(
                    manage,
                    people.map { app.maxly.data.ChatPerson(it.id, it.displayName) },
                    onBack = { managing = false },
                )
            } else {
            val model = viewModel(key = "profile-$profileFor") {
                ProfileViewModel(profileFor, chatTitle, container.profiles, container.messages, container.voicePlayer, container.files, account = container.account, contacts = container.contacts)
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
                onManage = {
                    channel = model.state.value.profile.kind == app.maxly.domain.ChatProfile.Kind.CHANNEL
                    managing = true
                },
            )
            }
        }
        else -> {
            val model = viewModel(key = "chat-$chatId") {
                ChatViewModel(
                    chatId, container.messages, fallbackTitle = chatTitle, voicePlayer = container.voicePlayer, files = container.files,
                    stickerRepository = container.stickers, stickerRecents = container.stickerRecents, drafts = container.drafts, draftSync = container.draftSync,
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
                openMessage = openMessage,
                onMessageOpened = onMessageOpened,
                onBlockComment = { postId, comment ->
                    container.chatAdmin.blockCommentAuthor(chatId, postId, comment.authorId, comment.id)
                },
                onStartCall = { peer, video -> container.scope.launch { container.callCenter.startCall(peer, video) } },
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
    onJoin = if (listed) null else ({ request(ChatAction.JOIN) }),
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
    onAddStory: () -> Unit,
    onFamilyProtection: (String) -> Unit,
    recoveryKey: Int,
    onOpenRecovery: () -> Unit,
    miniAppKey: Int,
    miniKind: String,
    onOpenMiniApp: (MiniApp.Kind) -> Unit,
    expanded: Boolean,
) {
    val securityModel = viewModel { SecurityViewModel(container.account) }
    val paneAccount by accountModel.state.collectAsStateWithLifecycle()
    val ghostModel = viewModel { GhostModeViewModel(container.ghostMode, container.ownPresence, foreground = container.windowShown) }
    val limits by container.accountLimits.state.collectAsStateWithLifecycle()
    // Мини-приложение занимает всю область: рядом со списком настроек ему тесно.
    val immersive = page == SettingsPage.MiniApp
    val showList = !immersive && (expanded || page == SettingsPage.Home)
    val showDetail = immersive || expanded || page != SettingsPage.Home
    val selected = when (page) {
        SettingsPage.Home -> null
        SettingsPage.About -> "about"
        SettingsPage.Devices -> "devices"
        SettingsPage.Appearance -> "appearance"
        SettingsPage.Profile -> "profile"
        SettingsPage.Privacy, SettingsPage.Blocked -> "privacy"
        SettingsPage.Security, SettingsPage.RecoveryEmail -> "security"
        SettingsPage.Storage -> "storage"
        SettingsPage.Folders -> "folders"
        SettingsPage.MiniApp -> if (miniKind == MiniApp.Kind.SFERUM.wire) "sferum" else "digital-id"
        SettingsPage.Messages -> "messages"
        SettingsPage.Keyboard -> "keyboard"
        SettingsPage.MyStories -> "my-stories"
    }
    Row(Modifier.fillMaxSize()) {
        if (showList) {
            Box(Modifier.then(if (expanded) Modifier.width(360.dp) else Modifier.weight(1f)).fillMaxHeight()) {
                SettingsScreen(
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
                    onMyStories = if (paneAccount.settings.storiesHistory) ({ onOpen(SettingsPage.MyStories) }) else null,
                    onMessages = { onOpen(SettingsPage.Messages) },
                    onKeyboard = { onOpen(SettingsPage.Keyboard) },
                    profileLink = profileLink,
                    accountLimits = limits,
                    ghost = ghostModel,
                    selected = selected,
                )
            }
            if (expanded) VerticalDivider()
        }
        if (showDetail) {
            Box(Modifier.weight(1f).fillMaxHeight()) {
    when (page) {
        SettingsPage.Home -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                "Выберите раздел",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        SettingsPage.Messages -> MessagesScreen(
            accountModel,
            loadCatalog = { container.messages.reactionCatalog() },
            onBack = onBack,
        )
        SettingsPage.About -> AboutScreen(onBack)
        SettingsPage.Keyboard -> KeyboardScreen(container.keyboard, onBack)
        SettingsPage.Devices -> DevicesScreen(container.sessions, onBack)
        SettingsPage.Appearance -> AppearanceScreen(container.appearance, onBack)
        SettingsPage.Profile -> ProfileEditScreen(accountModel, onBack, onLogout)
        SettingsPage.Privacy -> PrivacyScreen(accountModel, onBack, onBlocked = { onOpen(SettingsPage.Blocked) }, privateMode = container.privateMode, ghost = ghostModel)
        SettingsPage.Security -> SecurityScreen(securityModel, onBack, onChangeEmail = onOpenRecovery, account = accountModel, onFamilyProtection = onFamilyProtection)
        SettingsPage.MyStories -> app.maxly.ui.stories.MyStoriesScreen(
            viewModel { app.maxly.presentation.stories.MyStoriesViewModel(container.stories) },
            onCreate = onAddStory,
            onBack = onBack,
        )
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
        }
    }
}
