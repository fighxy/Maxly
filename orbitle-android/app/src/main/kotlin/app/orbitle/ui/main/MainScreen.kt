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
import app.orbitle.data.MessageRepository
import app.orbitle.presentation.chat.ChatViewModel
import app.orbitle.ui.chat.ChatScreen
import androidx.lifecycle.viewmodel.compose.viewModel
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
    chatList: ChatListViewModel,
    messages: MessageRepository,
    account: Account?,
    onLogout: () -> Unit,
) {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val chats by chatList.state.collectAsStateWithLifecycle()
    val showsBar = Tab.entries.any { it.route == route } || route == null
    Scaffold(
        bottomBar = {
            if (showsBar) {
                NavigationBar {
                    Tab.entries.forEach { tab ->
                        val selected = route == tab.route
                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = {
                                BadgedBox(badge = {
                                    if (tab == Tab.CHATS && chats.tabBadge > 0) Badge { Text(ChatListFormatter.compactCount(chats.tabBadge)) }
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
            composable(Tab.CHATS.route) { ChatListScreen(chatList, onOpenChat = { nav.navigate("chat/${it.id}") }) }
            composable(Tab.CALLS.route) { Soon(R.string.calls_title) }
            composable(Tab.CONTACTS.route) { Soon(R.string.contacts_title) }
            composable(Tab.SETTINGS.route) { SettingsScreen(account, onAbout = { nav.navigate("about") }, onLogout = onLogout) }
            composable("about") { AboutScreen(onBack = { nav.popBackStack() }) }
            composable("chat/{chatId}") { entry ->
                val chatId = entry.arguments?.getString("chatId").orEmpty()
                val model = viewModel(key = "chat-$chatId") { ChatViewModel(chatId, messages) }
                ChatScreen(model, onBack = { nav.popBackStack() })
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
