package app.orbitle.ui.contacts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import app.orbitle.presentation.contacts.ContactRow
import app.orbitle.presentation.contacts.ContactsUiState
import app.orbitle.presentation.contacts.ContactsViewModel
import app.orbitle.ui.chatlist.Placeholder
import app.orbitle.ui.components.Avatar
import app.orbitle.ui.components.privateBlur

/** Вкладка «Контакты»: разделы по буквам, поиск, «в сети». Нажатие открывает диалог. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactsScreen(model: ContactsViewModel, onOpen: (ContactRow) -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.appeared() }
    val snackbar = remember { androidx.compose.material3.SnackbarHostState() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    app.orbitle.ui.contacts.ContactActionsHost(model.actions) { text -> scope.launch { snackbar.showSnackbar(text) } }
    Scaffold(
        topBar = {
            if (state.isSearching) {
                val focus = remember { FocusRequester() }
                LaunchedEffect(Unit) { focus.requestFocus() }
                TopAppBar(
                    navigationIcon = { IconButton(onClick = { model.setSearching(false) }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Закрыть поиск") } },
                    title = {
                        TextField(
                            value = state.query,
                            onValueChange = model::setQuery,
                            placeholder = { Text("Имя или номер") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                            ),
                            modifier = Modifier.fillMaxWidth().focusRequester(focus),
                        )
                    },
                )
            } else {
                TopAppBar(
                    title = { Text("Контакты") },
                    actions = {
                        IconButton(onClick = model.actions::askAddByPhone) { Icon(Icons.Filled.PersonAdd, "Добавить по номеру") }
                        IconButton(onClick = { model.setSearching(true) }) { Icon(Icons.Filled.Search, "Поиск") }
                    },
                )
            }
        },
        snackbarHost = { androidx.compose.material3.SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.isSyncing && state.content == ContactsUiState.Content.READY,
            onRefresh = model::sync,
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            when {
                state.isFiltering -> LazyColumn(Modifier.fillMaxSize()) {
                    if (state.searchResults.isEmpty()) {
                        item { Text("Ничего не найдено", Modifier.padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    items(state.searchResults, key = { it.id }) { ContactItem(it, onRename = { model.askRename(it.id) }, onRemove = { model.askRemove(it.id) }) { onOpen(it) } }
                }
                state.content == ContactsUiState.Content.LOADING -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                state.content == ContactsUiState.Content.EMPTY -> LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Box(Modifier.fillParentMaxSize()) {
                            Placeholder(
                                icon = { Icon(Icons.Outlined.Person, null, Modifier.size(56.dp)) },
                                title = "Контактов пока нет",
                                text = "Контакты из MAX появятся здесь после синхронизации",
                            )
                        }
                    }
                }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    state.sections.forEach { section ->
                        item(key = "h-${section.letter}") {
                            Text(
                                section.letter,
                                Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        items(section.rows, key = { it.id }) { ContactItem(it, onRename = { model.askRename(it.id) }, onRemove = { model.askRemove(it.id) }) { onOpen(it) } }
                    }
                    item(key = "count") {
                        Text(
                            countText(state.count),
                            Modifier.fillMaxWidth().padding(24.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

private fun countText(count: Int): String =
    "$count ${app.orbitle.presentation.common.PresenceText.plural(count, "контакт", "контакта", "контактов")}"

@Composable
private fun ContactItem(row: ContactRow, onRename: () -> Unit, onRemove: () -> Unit, onClick: () -> Unit) {
    val privacy = app.orbitle.ui.components.LocalPrivateMode.current
    val hidden = privacy == app.orbitle.domain.PrivateModeDisplay.PLACEHOLDER
    val private = privacy != app.orbitle.domain.PrivateModeDisplay.VISIBLE
    ListItem(
        leadingContent = {
            Avatar(if (hidden) app.orbitle.presentation.settings.PrivateModeMask.avatar(row.avatar) else row.avatar, 44.dp, online = row.isOnline && !private, modifier = Modifier.privateBlur(privacy, 8.dp))
        },
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (hidden) app.orbitle.presentation.settings.PrivateModeMask.CONTACT_TITLE else row.title,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false).privateBlur(privacy, 7.dp),
                )
                if (row.isOfficial && !hidden) {
                    Spacer(Modifier.width(4.dp))
                    Icon(Icons.Filled.Verified, "Официальный аккаунт", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                }
            }
        },
        supportingContent = if (row.status.isEmpty()) null else ({
            Text(row.status, color = if (row.isOnline) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }),
        trailingContent = { app.orbitle.ui.contacts.ContactRowMenu(onRename, onRemove) },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable(onClick = onClick),
    )
}
