package app.orbitle.ui.main

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Call
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import app.orbitle.R
import android.net.Uri
import androidx.navigation.NavType
import androidx.navigation.navArgument
import app.orbitle.AppContainer
import app.orbitle.domain.Chat
import app.orbitle.presentation.calls.CallsViewModel
import app.orbitle.presentation.contacts.ContactsViewModel
import app.orbitle.ui.calls.CallsScreen
import app.orbitle.ui.contacts.ContactsScreen
import app.orbitle.ui.settings.AppearanceScreen
import app.orbitle.ui.settings.DevicesScreen
import app.orbitle.presentation.chat.ChatViewModel
import app.orbitle.presentation.profile.ProfileViewModel
import app.orbitle.ui.profile.ProfileChatActions
import app.orbitle.ui.profile.ProfileScreen
import app.orbitle.ui.chat.EmojiSupport
import app.orbitle.ui.chat.ChatAction
import app.orbitle.ui.chat.ChatScreen
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.presentation.settings.AccountSettingsViewModel
import app.orbitle.presentation.settings.RecoveryEmailViewModel
import app.orbitle.presentation.settings.SecurityViewModel
import app.orbitle.ui.settings.BlockedUsersScreen
import app.orbitle.ui.settings.PrivacyScreen
import app.orbitle.ui.settings.RecoveryEmailScreen
import app.orbitle.domain.MiniApp
import app.orbitle.presentation.settings.MiniAppViewModel
import app.orbitle.ui.settings.MiniAppScreen
import app.orbitle.ui.settings.SecurityScreen
import app.orbitle.ui.settings.StorageScreen
import app.orbitle.ui.settings.FoldersScreen
import app.orbitle.presentation.settings.FoldersViewModel
import app.orbitle.presentation.settings.StorageViewModel
import app.orbitle.ui.settings.ProfileEditScreen
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.presentation.chatlist.NewChatModel
import app.orbitle.ui.chatlist.ChatListScreen
import app.orbitle.ui.chatlist.Placeholder
import app.orbitle.ui.settings.AboutScreen
import app.orbitle.ui.settings.MessagesScreen
import app.orbitle.ui.settings.SettingsScreen
import app.orbitle.domain.Account
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import app.orbitle.domain.OutgoingStory
import app.orbitle.presentation.stories.StoriesViewModel
import app.orbitle.presentation.stories.StoryText
import app.orbitle.ui.stories.LocalStoryRings
import app.orbitle.ui.stories.StoriesStrip
import app.orbitle.ui.stories.StoryStack
import app.orbitle.ui.stories.StoryComposer
import app.orbitle.ui.stories.StoryFiles
import app.orbitle.ui.stories.StoryRings
import app.orbitle.ui.stories.StoryViewer
import kotlinx.coroutines.launch

/** Вкладки нижней панели. */
enum class Tab(val route: String, val title: Int, val icon: ImageVector, val selectedIcon: ImageVector) {
    CHATS("chats", R.string.tab_chats, Icons.Outlined.ChatBubbleOutline, Icons.AutoMirrored.Filled.Chat),
    CALLS("calls", R.string.tab_calls, Icons.Outlined.Call, Icons.Filled.Call),
    CONTACTS("contacts", R.string.tab_contacts, Icons.Outlined.Person, Icons.Filled.Person),
    SETTINGS("settings", R.string.tab_settings, Icons.Outlined.Settings, Icons.Filled.Settings),
}

/** Главный экран после входа: вкладки «Чаты», «Звонки», «Контакты», «Настройки». */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    container: AppContainer,
    chatList: ChatListViewModel,
    account: Account?,
    onLogout: () -> Unit,
) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val chats by chatList.state.collectAsStateWithLifecycle()
    val callsModel = viewModel { CallsViewModel(container.calls, container.callMarks, connection = container.session.connection) }
    val calls by callsModel.state.collectAsStateWithLifecycle()
    val accountModel = viewModel { AccountSettingsViewModel(container.account) }
    val securityModel = viewModel { SecurityViewModel(container.account) }
    val accountState by accountModel.state.collectAsStateWithLifecycle()
    val contactsModel = viewModel { ContactsViewModel(container.contacts, { container.messages.currentUserId }, chats = container.chats) }
    val phoneBookModel = viewModel { container.phoneBookModel() }
    val newChat = viewModel(key = "new-chat") { NewChatModel(container.contacts, container.chats) { container.messages.currentUserId } }
    val privatePrefs by container.privateMode.state.collectAsStateWithLifecycle()
    val privateDisplay = app.orbitle.data.PrivateModeSettings.display(privatePrefs, canBlur = android.os.Build.VERSION.SDK_INT >= 31)
    val showsBar = Tab.entries.any { it.route == route } || route == null
    // Истории: одна модель на список, шапку чата и профиль.
    val storiesModel = viewModel { StoriesViewModel(container.stories, container.session.connection) }
    val stories by storiesModel.state.collectAsStateWithLifecycle()
    var composingStory by remember { mutableStateOf<OutgoingStory?>(null) }
    val context = LocalContext.current
    val storyScope = rememberCoroutineScope()
    val pickStory = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) storyScope.launch {
            composingStory = StoryFiles.import(context, uri)
            if (composingStory == null) Toast.makeText(context, "Не удалось открыть файл", Toast.LENGTH_SHORT).show()
        }
    }
    val addStory = { pickStory.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }
    LaunchedEffect(stories.message) {
        val text = stories.message ?: return@LaunchedEffect
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
        storiesModel.consumeMessage()
    }
    // Действие из профиля чата (поиск, «О чате», звонок, очистка, удаление): чат откроет его после возврата.
    var chatAction by remember { mutableStateOf<Pair<String, ChatAction>?>(null) }
    // Найденное в общем поиске сообщение: чат откроется на нём (id чата, id сообщения, время).
    var openMessage by remember { mutableStateOf<Triple<String, String, Long>?>(null) }
    fun openChat(id: String, title: String? = null) {
        nav.navigate(if (title == null) "chat/$id" else "chat/$id?title=${Uri.encode(title)}")
    }
    fun openTab(tab: Tab) {
        nav.navigate(tab.route) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    Scaffold(
        bottomBar = {
            if (showsBar) {
                NavigationBar {
                    Tab.entries.forEach { tab ->
                        val selected = route == tab.route
                        NavigationBarItem(
                            selected = selected,
                            onClick = { openTab(tab) },
                            icon = {
                                BadgedBox(badge = {
                                    if (tab == Tab.CHATS && chats.tabBadge > 0) Badge { Text(ChatListFormatter.compactCount(chats.tabBadge)) }
                                    if (tab == Tab.CALLS && calls.unseenMissed > 0) Badge { Text(ChatListFormatter.compactCount(calls.unseenMissed)) }
                                }) {
                                    Icon(if (selected) tab.selectedIcon else tab.icon, contentDescription = null)
                                }
                            },
                            label = { Text(stringResource(tab.title)) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        androidx.compose.runtime.CompositionLocalProvider(
            app.orbitle.ui.components.LocalPrivateMode provides privateDisplay,
            LocalStoryRings provides StoryRings(stories, storiesModel::open, storiesModel::loadRing, storiesModel::loadOwner),
        ) {
        NavHost(nav, startDestination = Tab.CHATS.route, modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable(Tab.CHATS.route) {
                val selfAvatar = StoryText.avatar(account?.id ?: container.messages.currentUserId.orEmpty(), account?.displayName.orEmpty(), account?.avatarUrl)
                val stackItems = listOfNotNull(stories.own?.let { selfAvatar to it }) + stories.rings.map { StoryText.avatar(it) to it }
                ChatListScreen(
                    chatList,
                    onOpenChat = { openChat(it.id) },
                    onOpenFound = { openChat(it.id, it.title) },
                    onOpenMessage = {
                        openMessage = Triple(it.chatId, it.messageId, it.timeMs)
                        openChat(it.chatId)
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
                        )
                    },
                    storyStack = if (stackItems.isEmpty()) null else ({ StoryStack(stackItems) }),
                    onAddStory = addStory,
                )
            }
            composable(Tab.CALLS.route) {
                val context = androidx.compose.ui.platform.LocalContext.current
                CallsScreen(
                    callsModel,
                    onOpenChat = { openChat(it) },
                    onJoin = { app.orbitle.calls.AndroidCalls.join(container, it) },
                    onCall = { row, video ->
                        app.orbitle.calls.AndroidCalls.start(container, app.orbitle.presentation.calls.CallPeerInfo(row.peerId, row.name, row.avatarUrl), video)
                    },
                    onShareLink = { app.orbitle.calls.AndroidCalls.share(context, it) },
                )
            }
            composable(Tab.CONTACTS.route) {
                ContactsScreen(
                    contactsModel,
                    onOpen = { row -> contactsModel.prepare(row.id, row.title)?.let { openChat(it, row.title) } },
                    phoneBook = phoneBookModel,
                )
            }
            composable(Tab.SETTINGS.route) {
                val limits by container.accountLimits.state.collectAsStateWithLifecycle()
                SettingsScreen(
                    account,
                    onAbout = { nav.navigate("about") },
                    onLogout = onLogout,
                    onSaved = { openChat(Chat.SAVED_MESSAGES_ID) },
                    onContacts = { openTab(Tab.CONTACTS) },
                    onDevices = { nav.navigate("devices") },
                    onAppearance = { nav.navigate("appearance") },
                    onEditProfile = { nav.navigate("profile-edit") },
                    onPrivacy = { nav.navigate("privacy") },
                    onSecurity = { nav.navigate("security") },
                    onDigitalId = { nav.navigate("mini-app/${MiniApp.Kind.DIGITAL_ID.wire}") },
                    onSferum = { nav.navigate("mini-app/${MiniApp.Kind.SFERUM.wire}") },
                    onStorage = { nav.navigate("storage") },
                    onFolders = { nav.navigate("folders") },
                    onMessages = { nav.navigate("messages") },
                    profileLink = app.orbitle.presentation.settings.ProfileLink.link(accountState.settings.inviteLink, account?.link),
                    accountLimits = limits,
                )
            }
            composable("messages") {
                MessagesScreen(
                    accountModel,
                    loadCatalog = { container.messages.reactionCatalog() },
                    onBack = { nav.popBackStack() },
                )
            }
            composable("profile-edit") { ProfileEditScreen(accountModel, onBack = { nav.popBackStack() }, onLogout = onLogout) }
            composable("privacy") { PrivacyScreen(accountModel, onBack = { nav.popBackStack() }, onBlocked = { nav.navigate("blocked") }, privateMode = container.privateMode) }
            composable("security") {
                SecurityScreen(securityModel, onBack = { nav.popBackStack() }, onChangeEmail = { nav.navigate("recovery-email") })
            }
            composable(
                "mini-app/{kind}",
                arguments = listOf(navArgument("kind") { type = NavType.StringType }),
            ) { entry ->
                val kind = MiniApp.Kind.fromWire(entry.arguments?.getString("kind")) ?: return@composable
                MiniAppScreen(viewModel { MiniAppViewModel(kind, container.account) }) { nav.popBackStack() }
            }
            composable("recovery-email") {
                val flow = viewModel { RecoveryEmailViewModel(container.account) }
                RecoveryEmailScreen(
                    flow,
                    onBack = { nav.popBackStack() },
                    onDone = { status ->
                        securityModel.apply(status)
                        nav.popBackStack()
                    },
                )
            }
            composable("storage") { StorageScreen(viewModel { StorageViewModel(container.storage) }, onBack = { nav.popBackStack() }) }
            composable("folders") {
                FoldersScreen(
                    viewModel { FoldersViewModel(container.folders) },
                    count = chatList::folderCount,
                    candidates = chatList::folderCandidates,
                    onBack = { nav.popBackStack() },
                )
            }
            composable("blocked") { BlockedUsersScreen(accountModel, onBack = { nav.popBackStack() }) }
            composable("about") { AboutScreen(onBack = { nav.popBackStack() }) }
            composable("devices") { DevicesScreen(container.sessions, onBack = { nav.popBackStack() }) }
            composable("appearance") { AppearanceScreen(container.appearance, onBack = { nav.popBackStack() }) }
            composable(
                "chat/{chatId}?title={title}",
                arguments = listOf(navArgument("title") { type = NavType.StringType; nullable = true; defaultValue = null }),
            ) { entry ->
                val chatId = entry.arguments?.getString("chatId").orEmpty()
                val title = entry.arguments?.getString("title")
                val model = viewModel(key = "chat-$chatId") { ChatViewModel(
                        chatId, container.messages, fallbackTitle = title, voicePlayer = container.voicePlayer, files = container.files,
                        stickerRepository = container.stickers, stickerRecents = container.stickerRecents, drafts = container.drafts, draftSync = container.draftSync,
                        emojiSupported = EmojiSupport::canDraw, comments = container.comments,
                        mediaSaver = container.mediaSaver,
                        chats = container.chats,
                        profiles = container.profiles,
                    ) }
                ChatScreen(
                    model,
                    onBack = { nav.popBackStack() },
                    onOpenProfile = { nav.navigate("profile/$chatId?fromChat=true") },
                    mediaUserAgent = container.videoSourceUserAgent(),
                    forwardTargets = { chatList.forwardTargets(excluding = chatId) },
                    onDisablePrivateMode = { container.privateMode.setEnabled(false) },
                    quickReaction = accountState.settings.quickReaction.takeIf { accountState.settings.quickReactionEnabled },
                    requestedAction = chatAction?.takeIf { it.first == chatId }?.second,
                    onActionHandled = { chatAction = null },
                    openMessage = openMessage?.takeIf { it.first == chatId }?.let { it.second to it.third },
                    onMessageOpened = { openMessage = null },
                    onBlockComment = { postId, comment ->
                        container.chatAdmin.blockCommentAuthor(chatId, postId, comment.authorId, comment.id)
                    },
                    onStartCall = { peer, video -> app.orbitle.calls.AndroidCalls.start(container, peer, video) },
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
            composable(
                "profile/{chatId}?fromChat={fromChat}&title={title}",
                arguments = listOf(
                    navArgument("fromChat") { type = NavType.BoolType; defaultValue = false },
                    navArgument("title") { type = NavType.StringType; nullable = true; defaultValue = null },
                ),
            ) { entry ->
                val chatId = entry.arguments?.getString("chatId").orEmpty()
                val fromChat = entry.arguments?.getBoolean("fromChat") == true
                val title = entry.arguments?.getString("title")
                val model = viewModel(key = "profile-$chatId") {
                    ProfileViewModel(chatId, title, container.profiles, container.messages, container.voicePlayer, container.files, account = container.account, contacts = container.contacts)
                }
                ProfileScreen(
                    model,
                    onBack = { nav.popBackStack() },
                    // Из чата профиль закрывается назад, «Написать» нужна только снаружи.
                    onWrite = if (fromChat) null else ({ openChat(chatId, title) }),
                    mediaUserAgent = container.videoSourceUserAgent(),
                    chatActions = if (fromChat) profileChatActions(listed = chatList.isListed(chatId)) { action ->
                        chatAction = chatId to action
                        nav.popBackStack()
                    } else null,
                    onManage = {
                        val channel = model.state.value.profile.kind == app.orbitle.domain.ChatProfile.Kind.CHANNEL
                        nav.navigate("manage/$chatId?channel=$channel")
                    },
                )
            }
            composable(
                "manage/{chatId}?channel={channel}",
                arguments = listOf(navArgument("channel") { type = NavType.BoolType; defaultValue = false }),
            ) { entry ->
                val chatId = entry.arguments?.getString("chatId").orEmpty()
                val channel = entry.arguments?.getBoolean("channel") == true
                val manage = viewModel(key = "manage-$chatId") {
                    app.orbitle.presentation.profile.ChatManageViewModel(
                        chatId, channel, container.messages.currentUserId, container.chatAdmin,
                    )
                }
                val people by container.contacts.contacts.collectAsStateWithLifecycle(initialValue = emptyList())
                app.orbitle.ui.profile.ManageRoute(
                    manage,
                    people.map { app.orbitle.data.ChatPerson(it.id, it.displayName) },
                    onBack = { nav.popBackStack() },
                )
            }
        }
        }
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Soon(title: Int) {
    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(title)) }) },
        contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0),
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Placeholder(icon = { Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.size(56.dp)) }, title = stringResource(R.string.soon))
        }
    }
}

/** Действия профиля, открытого из чата: каждое закрывает профиль и открывается в чате. */
internal fun profileChatActions(listed: Boolean = true, request: (ChatAction) -> Unit) = ProfileChatActions(
    onSearch = { request(ChatAction.SEARCH) },
    onTools = { request(ChatAction.TOOLS) },
    onCall = { request(ChatAction.CALL) },
    onClearHistory = { request(ChatAction.CLEAR_HISTORY) },
    onDeleteChat = { request(ChatAction.DELETE_CHAT) },
    onLeave = if (listed) ({ request(ChatAction.LEAVE) }) else null,
    onJoin = if (listed) null else ({ request(ChatAction.JOIN) }),
)
