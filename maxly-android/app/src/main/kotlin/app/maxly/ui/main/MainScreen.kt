package app.maxly.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.activity.compose.BackHandler
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldDestinationItem
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
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
import app.maxly.R
import android.net.Uri
import androidx.navigation.NavType
import androidx.navigation.navArgument
import app.maxly.AppContainer
import app.maxly.domain.Chat
import app.maxly.presentation.calls.CallsViewModel
import app.maxly.presentation.contacts.ContactsViewModel
import app.maxly.ui.calls.CallsScreen
import app.maxly.ui.contacts.ContactsScreen
import app.maxly.ui.settings.AppearanceScreen
import app.maxly.ui.settings.DevicesScreen
import app.maxly.presentation.chat.BotAppRequest
import app.maxly.presentation.chat.ChatViewModel
import app.maxly.presentation.profile.ProfileViewModel
import app.maxly.ui.profile.ProfileChatActions
import app.maxly.ui.profile.ProfileScreen
import app.maxly.ui.chat.EmojiSupport
import app.maxly.ui.chat.ChatAction
import app.maxly.ui.chat.ChatScreen
import androidx.lifecycle.viewmodel.compose.viewModel
import app.maxly.presentation.settings.AccountSettingsViewModel
import app.maxly.presentation.settings.RecoveryEmailViewModel
import app.maxly.presentation.settings.GhostModeViewModel
import app.maxly.presentation.settings.SecurityViewModel
import app.maxly.ui.settings.BlockedUsersScreen
import app.maxly.ui.settings.PrivacyScreen
import app.maxly.ui.settings.RecoveryEmailScreen
import app.maxly.domain.MiniApp
import app.maxly.presentation.settings.MiniAppViewModel
import app.maxly.ui.settings.MiniAppScreen
import app.maxly.ui.settings.SecurityScreen
import app.maxly.ui.settings.StorageScreen
import app.maxly.ui.settings.FoldersScreen
import app.maxly.presentation.settings.FoldersViewModel
import app.maxly.presentation.settings.StorageViewModel
import app.maxly.ui.settings.ProfileEditScreen
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.presentation.chatlist.ChatListViewModel
import app.maxly.presentation.chatlist.NewChatModel
import app.maxly.ui.chatlist.ChatListScreen
import app.maxly.ui.chatlist.Placeholder
import app.maxly.ui.settings.AboutScreen
import app.maxly.ui.settings.MessagesScreen
import app.maxly.ui.settings.SettingsScreen
import app.maxly.domain.Account
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import app.maxly.domain.OutgoingStory
import app.maxly.presentation.stories.StoriesViewModel
import app.maxly.presentation.stories.StoryText
import app.maxly.ui.stories.LocalStoryRings
import app.maxly.ui.stories.StoriesStrip
import app.maxly.ui.stories.StoryStack
import app.maxly.ui.stories.StoryComposer
import app.maxly.ui.stories.MyStoriesScreen
import app.maxly.ui.stories.StoryFiles
import app.maxly.ui.stories.StoryRings
import app.maxly.ui.stories.StoryViewer
import kotlinx.coroutines.launch

/** Вкладки нижней панели. */
enum class Tab(val route: String, val title: Int, val icon: ImageVector, val selectedIcon: ImageVector) {
    CHATS("chats", R.string.tab_chats, Icons.Outlined.ChatBubbleOutline, Icons.AutoMirrored.Filled.Chat),
    CALLS("calls", R.string.tab_calls, Icons.Outlined.Call, Icons.Filled.Call),
    CONTACTS("contacts", R.string.tab_contacts, Icons.Outlined.Person, Icons.Filled.Person),
    SETTINGS("settings", R.string.tab_settings, Icons.Outlined.Settings, Icons.Filled.Settings),
}

/** Главный экран после входа: вкладки «Чаты», «Звонки», «Контакты», «Настройки». */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3AdaptiveApi::class)
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
    val ghostModel = viewModel { GhostModeViewModel(container.ghostMode, container.ownPresence) }
    val accountState by accountModel.state.collectAsStateWithLifecycle()
    val contactsModel = viewModel { ContactsViewModel(container.contacts, { container.messages.currentUserId }, chats = container.chats) }
    val phoneBookModel = viewModel { container.phoneBookModel() }
    val newChat = viewModel(key = "new-chat") { NewChatModel(container.contacts, container.chats) { container.messages.currentUserId } }
    val privatePrefs by container.privateMode.state.collectAsStateWithLifecycle()
    val privateDisplay = app.maxly.data.PrivateModeSettings.display(privatePrefs, canBlur = android.os.Build.VERSION.SDK_INT >= 31)
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
    var listBotApp by remember { mutableStateOf<BotAppRequest?>(null) }
    // Найденное в общем поиске сообщение: чат откроется на нём (id чата, id сообщения, время).
    var openMessage by remember { mutableStateOf<Triple<String, String, Long>?>(null) }
    fun openChat(id: String, title: String? = null) {
        nav.navigate(if (title == null) "chat/$id" else "chat/$id?title=${Uri.encode(title)}")
    }
    // Нажали на уведомление о сообщении: открыть его чат.
    val requestedChat by container.chatOpenRequests.pending.collectAsStateWithLifecycle()
    LaunchedEffect(requestedChat) {
        val id = requestedChat ?: return@LaunchedEffect
        openChat(id)
        container.chatOpenRequests.consume(id)
    }
    fun openTab(tab: Tab) {
        nav.navigate(tab.route) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    // Широкое окно: список чатов остаётся слева, пока открыты чат, профиль или управление.
    val paneDirective = calculatePaneScaffoldDirective(currentWindowAdaptiveInfo())
    val chatSection = route == null || route == Tab.CHATS.route ||
        route.startsWith("chat/") || route.startsWith("profile/") || route.startsWith("manage/")
    val chatSplit = chatSection && paneDirective.maxHorizontalPartitions > 1
    val suiteType = if (showsBar || chatSplit) {
        NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(currentWindowAdaptiveInfo())
    } else {
        NavigationSuiteType.None
    }
    @Composable
    fun ChatsPane() {
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
                openMessage = Triple(it.chatId, it.messageId, it.timeMs)
                openChat(it.chatId)
            },
            privateMode = privatePrefs,
            onTogglePrivateMode = container.privateMode::toggle,
            newChat = newChat,
            onOpenCreated = { id, title -> openChat(id, title) },
            channelSetup = { id, done ->
                val setup = viewModel(key = "channel-setup-$id") {
                    app.maxly.presentation.chatlist.ChannelSetupModel(id, container.chatAdmin, container.messages, container.contacts) { container.messages.currentUserId }
                }
                app.maxly.ui.chatlist.ChannelSetupSheet(setup, chats.items.filter { it.id != id }, onDone = done)
            },
            storiesHeader = {
                StoriesStrip(
                    stories,
                    self = selfAvatar,
                    onOpen = storiesModel::open,
                    onAdd = addStory,
                    onArchive = { nav.navigate("my-stories") },
                )
            },
            storyStack = if (stackItems.isEmpty()) null else ({ StoryStack(stackItems) }),
            onAddStory = addStory,
            onRetryLogin = { container.scope.launch { container.session.retryLogin() } },
            onLogout = onLogout,
        )
    }
    NavigationSuiteScaffold(
        modifier = Modifier.fillMaxSize(),
        layoutType = suiteType,
        navigationSuiteItems = {
            Tab.entries.forEach { tab ->
                val selected = when (tab) {
                    Tab.CHATS -> chatSplit || route == null || route == Tab.CHATS.route
                    else -> route == tab.route
                }
                val count = when {
                    tab == Tab.CHATS && chats.tabBadge > 0 -> chats.tabBadge
                    tab == Tab.CALLS && calls.unseenMissed > 0 -> calls.unseenMissed
                    else -> 0
                }
                item(
                    selected = selected,
                    onClick = { openTab(tab) },
                    icon = { Icon(if (selected) tab.selectedIcon else tab.icon, contentDescription = null) },
                    label = { Text(stringResource(tab.title)) },
                    badge = if (count > 0) {
                        { Badge { Text(ChatListFormatter.compactCount(count)) } }
                    } else {
                        null
                    },
                )
            }
        },
    ) {
    // Внутренний Scaffold оставляет прежние отступы статус-бара: экраны сами их обнуляют.
    Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
        androidx.compose.runtime.CompositionLocalProvider(
            app.maxly.ui.components.LocalPrivateMode provides privateDisplay,
            LocalStoryRings provides StoryRings(stories, storiesModel::open, storiesModel::loadRing, storiesModel::loadOwner, storiesModel::hideOwner),
        ) {
        ChatListDetail(
            split = chatSplit,
            list = { ChatsPane() },
            detail = {
        NavHost(nav, startDestination = Tab.CHATS.route, modifier = Modifier.padding(padding).consumeWindowInsets(padding).fillMaxSize()) {
            composable(Tab.CHATS.route) {
                if (chatSplit) {
                    Placeholder(
                        icon = { Icon(Icons.Outlined.ChatBubbleOutline, null, Modifier.size(56.dp)) },
                        title = "Выберите чат",
                    )
                } else {
                    ChatsPane()
                }
            }
            composable(Tab.CALLS.route) {
                val context = androidx.compose.ui.platform.LocalContext.current
                CallsScreen(
                    callsModel,
                    onOpenChat = { openChat(it) },
                    onJoin = { app.maxly.calls.AndroidCalls.join(container, it) },
                    onCall = { row, video ->
                        app.maxly.calls.AndroidCalls.start(container, app.maxly.presentation.calls.CallPeerInfo(row.peerId, row.name, row.avatarUrl), video)
                    },
                    onShareLink = { app.maxly.calls.AndroidCalls.share(context, it) },
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
                    onMyStories = { nav.navigate("my-stories") },
                    onMessages = { nav.navigate("messages") },
                    onNotifications = { nav.navigate("notifications") },
                    profileLink = app.maxly.presentation.settings.ProfileLink.link(accountState.settings.inviteLink, account?.link),
                    accountLimits = limits,
                    ghost = ghostModel,
                )
            }
            composable("notifications") {
                val enabled by container.notificationSettings.enabled.collectAsStateWithLifecycle()
                // Разрешение могли поменять в настройках Android, пока экран был открыт.
                val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
                val resumed by lifecycle.currentStateFlow.collectAsStateWithLifecycle()
                val allowed = remember(resumed) { androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled() }
                app.maxly.ui.settings.NotificationsScreen(
                    enabled = enabled,
                    onEnabledChange = container.notificationSettings::setEnabled,
                    explanation = "Свёрнутый Maxly остаётся на связи: входящие звонки и уведомления о новых сообщениях приходят, " +
                        "как при открытом приложении. Сервер Max шлёт пуши только своему приложению, поэтому Maxly держит " +
                        "соединение сам — это немного расходует батарею. В шторке при этом видно тихое уведомление «Maxly на связи»; " +
                        "его можно скрыть в настройках Android (канал «Фоновая связь»).",
                    onBack = { nav.popBackStack() },
                    blocked = if (allowed) null else "Уведомления Maxly запрещены в настройках Android. Звонки и сообщения в фоне приходят, но не показываются.",
                    onOpenSystemSettings = {
                        context.startActivity(
                            android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName),
                        )
                    },
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
            composable("privacy") { PrivacyScreen(accountModel, onBack = { nav.popBackStack() }, onBlocked = { nav.navigate("blocked") }, privateMode = container.privateMode, ghost = ghostModel) }
            composable("security") {
                SecurityScreen(
                    securityModel,
                    onBack = { nav.popBackStack() },
                    onChangeEmail = { nav.navigate("recovery-email") },
                    account = accountModel,
                    onFamilyProtection = { botId -> listBotApp = BotAppRequest(botId, "", null, "Семейная защита") },
                )
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
            composable("my-stories") {
                MyStoriesScreen(
                    viewModel { app.maxly.presentation.stories.MyStoriesViewModel(container.stories) },
                    onCreate = addStory,
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
                    onOpenParticipant = { id, name ->
                        nav.navigate("profile/$id?title=${android.net.Uri.encode(name)}")
                    },
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
                    onStartCall = { peer, video -> app.maxly.calls.AndroidCalls.start(container, peer, video) },
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
                    chatActions = if (fromChat) profileChatActions(chatId, chatList, chats.items) { action ->
                        chatAction = chatId to action
                        nav.popBackStack()
                    } else null,
                    onManage = {
                        val channel = model.state.value.profile.kind == app.maxly.domain.ChatProfile.Kind.CHANNEL
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
                    app.maxly.presentation.profile.ChatManageViewModel(
                        chatId, channel, container.messages.currentUserId, container.chatAdmin,
                    )
                }
                val people by container.contacts.contacts.collectAsStateWithLifecycle(initialValue = emptyList())
                app.maxly.ui.profile.ManageRoute(
                    manage,
                    people.map { app.maxly.data.ChatPerson(it.id, it.displayName) },
                    onBack = { nav.popBackStack() },
                )
            }
        }
            },
        )
        }
    }
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
    stories.viewer?.let { viewer ->
        StoryViewer(
            viewer,
            userAgent = container.videoSourceUserAgent(),
            actions = app.maxly.presentation.stories.StoryViewerActions.of(storiesModel) { ring ->
                // Профиль человека — его диалог (`свой id xor id автора`), группы и канала — сам чат.
                val me = container.stories.currentUserId?.toLongOrNull()
                val owner = ring.owner.id.toLongOrNull()
                val chat = if (ring.owner.type == app.maxly.domain.StoryOwner.Type.USER && me != null && owner != null) (me xor owner).toString() else ring.owner.id
                nav.navigate("profile/$chat")
            },
            busy = stories.busy,
            reportReasons = stories.reportReasons,
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

/**
 * На широком окне список и открытый раздел стоят рядом. На узком видна только правая часть,
 * где живёт прежний NavHost. Назад по-прежнему обрабатывает он, а не навигатор панелей.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
private fun ChatListDetail(
    split: Boolean,
    list: @Composable () -> Unit,
    detail: @Composable () -> Unit,
) {
    val base = calculatePaneScaffoldDirective(currentWindowAdaptiveInfo())
    val directive = if (split) base else base.copy(maxHorizontalPartitions = 1)
    val navigator = rememberListDetailPaneScaffoldNavigator<String>(
        scaffoldDirective = directive,
        initialDestinationHistory = listOf(
            ThreePaneScaffoldDestinationItem(ListDetailPaneScaffoldRole.Detail, DetailKey),
        ),
    )
    LaunchedEffect(navigator.currentDestination?.pane) {
        if (navigator.currentDestination?.pane != ListDetailPaneScaffoldRole.Detail) {
            navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, DetailKey)
        }
    }
    ListDetailPaneScaffold(
        directive = navigator.scaffoldDirective,
        scaffoldState = navigator.scaffoldState,
        listPane = { AnimatedPane { if (split) list() } },
        detailPane = { AnimatedPane { detail() } },
    )
}

private const val DetailKey = "detail"

/**
 * Действия профиля, открытого из чата. Поиск, звонки, стирание и удаление закрывают профиль и
 * открываются в чате; звук и папки меняются на месте через список чатов.
 */
internal fun profileChatActions(
    chatId: String,
    chatList: ChatListViewModel,
    /** Строки списка сейчас: звук чата и куда отправить контакт. */
    items: List<app.maxly.presentation.chatlist.ChatListItem>,
    request: (ChatAction) -> Unit,
): ProfileChatActions {
    val listed = chatList.isListed(chatId)
    return ProfileChatActions(
        onSearch = { request(ChatAction.SEARCH) },
        onTools = { request(ChatAction.TOOLS) },
        onCall = { request(ChatAction.AUDIO_CALL) },
        onClearHistory = { request(ChatAction.CLEAR_HISTORY) },
        onDeleteChat = { request(ChatAction.DELETE_CHAT) },
        onLeave = if (listed) ({ request(ChatAction.LEAVE) }) else null,
        onJoin = if (listed) null else ({ request(ChatAction.JOIN) }),
        onVideoCall = { request(ChatAction.VIDEO_CALL) },
        muted = if (listed) items.firstOrNull { it.id == chatId }?.isMuted ?: chatList.isMuted(chatId) else null,
        onMuteFor = { chatList.muteFor(chatId, it) },
        onUnmute = { chatList.toggleMute(chatId) },
        folders = if (listed) chatList.folderChoices(chatId) else null,
        onToggleFolder = { chatList.toggleFolder(chatId, it) },
        onCreateFolder = { chatList.createFolder(chatId, it) },
        shareTargets = { items },
    )
}
