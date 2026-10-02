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
import app.orbitle.ui.profile.ProfileScreen
import app.orbitle.ui.chat.EmojiSupport
import app.orbitle.ui.chat.ChatScreen
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.presentation.settings.AccountSettingsViewModel
import app.orbitle.ui.settings.BlockedUsersScreen
import app.orbitle.ui.settings.PrivacyScreen
import app.orbitle.ui.settings.StorageScreen
import app.orbitle.ui.settings.FoldersScreen
import app.orbitle.presentation.settings.FoldersViewModel
import app.orbitle.presentation.settings.StorageViewModel
import app.orbitle.ui.settings.ProfileEditScreen
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.ui.chatlist.ChatListScreen
import app.orbitle.ui.chatlist.Placeholder
import app.orbitle.ui.settings.AboutScreen
import app.orbitle.ui.settings.SettingsScreen
import app.orbitle.domain.Account

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
    val callsModel = viewModel { CallsViewModel(container.calls, container.callMarks) }
    val calls by callsModel.state.collectAsStateWithLifecycle()
    val accountModel = viewModel { AccountSettingsViewModel(container.account) }
    val contactsModel = viewModel { ContactsViewModel(container.contacts, { container.messages.currentUserId }) }
    val showsBar = Tab.entries.any { it.route == route } || route == null
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
        NavHost(nav, startDestination = Tab.CHATS.route, modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable(Tab.CHATS.route) { ChatListScreen(chatList, onOpenChat = { openChat(it.id) }) }
            composable(Tab.CALLS.route) { CallsScreen(callsModel, onOpenChat = { openChat(it) }) }
            composable(Tab.CONTACTS.route) {
                ContactsScreen(contactsModel, onOpen = { row -> contactsModel.chatId(row.id)?.let { openChat(it, row.title) } })
            }
            composable(Tab.SETTINGS.route) {
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
                    onStorage = { nav.navigate("storage") },
                    onFolders = { nav.navigate("folders") },
                )
            }
            composable("profile-edit") { ProfileEditScreen(accountModel, onBack = { nav.popBackStack() }) }
            composable("privacy") { PrivacyScreen(accountModel, onBack = { nav.popBackStack() }, onBlocked = { nav.navigate("blocked") }) }
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
                        stickerRepository = container.stickers, stickerRecents = container.stickerRecents, drafts = container.drafts,
                        emojiSupported = EmojiSupport::canDraw, comments = container.comments,
                        mediaSaver = container.mediaSaver,
                    ) }
                ChatScreen(
                    model,
                    onBack = { nav.popBackStack() },
                    onOpenProfile = { nav.navigate("profile/$chatId?fromChat=true") },
                    mediaUserAgent = container.videoSourceUserAgent(),
                    forwardTargets = { chatList.forwardTargets(excluding = chatId) },
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
                    ProfileViewModel(chatId, title, container.profiles, container.messages, container.voicePlayer, container.files)
                }
                ProfileScreen(
                    model,
                    onBack = { nav.popBackStack() },
                    // Из чата профиль закрывается назад, «Написать» нужна только снаружи.
                    onWrite = if (fromChat) null else ({ openChat(chatId, title) }),
                    mediaUserAgent = container.videoSourceUserAgent(),
                )
            }
        }
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
