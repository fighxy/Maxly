package app.maxly.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.maxly.data.ChatPerson
import app.maxly.presentation.profile.MemberListState

/** Поле поиска по участникам. */
@Composable
fun MemberSearchField(query: String, onQuery: (String) -> Unit, modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = query,
        onValueChange = onQuery,
        placeholder = { Text("Поиск участников") },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        trailingIcon = if (query.isEmpty()) null else ({
            IconButton(onClick = { onQuery("") }) { Icon(Icons.Default.Close, contentDescription = "Очистить поиск") }
        }),
        singleLine = true,
        modifier = modifier.fillMaxWidth(),
    )
}

/**
 * Строка участника: имя, роль («владелец», «админ») и присутствие [presence] одной строкой:
 * «админ · в сети». Без известного присутствия — только роль.
 */
@Composable
fun MemberRow(
    person: ChatPerson,
    presence: String? = null,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    val role = MemberListState.roleLabel(person)
    val primary = MaterialTheme.colorScheme.primary
    val line = buildAnnotatedString {
        if (role.isNotEmpty()) withStyle(SpanStyle(color = primary)) { append(role) }
        if (presence != null) {
            if (role.isNotEmpty()) append(" · ")
            if (person.isOnline) withStyle(SpanStyle(color = primary)) { append(presence) } else append(presence)
        }
    }
    ListItem(
        headlineContent = { Text(person.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        supportingContent = if (line.isEmpty()) null else ({ Text(line, maxLines = 1, overflow = TextOverflow.Ellipsis) }),
        trailingContent = trailing,
        modifier = modifier,
    )
}

/**
 * Хвост списка участников внутри `LazyColumn`: подпись пустого списка, ошибка, индикатор и
 * следующая страница — сама, когда хвост показался, и кнопкой.
 */
fun LazyListScope.memberListTail(state: MemberListState, onMore: () -> Unit) {
    state.emptyText?.let { text ->
        item(key = "members-empty") { Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 8.dp)) }
    }
    state.error?.let { text ->
        item(key = "members-error") { Text(text, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(vertical = 4.dp)) }
    }
    if (state.loading || state.searching) {
        item(key = "members-progress") {
            Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            }
        }
    } else if (state.hasMore && !state.isSearch) {
        item(key = "members-more") {
            LaunchedEffect(state.members.size) { onMore() }
            TextButton(onClick = onMore) { Text("Показать ещё") }
        }
    }
}

/** Участники с поиском в ограниченной по высоте области (лист «О чате»). */
@Composable
fun MemberListBlock(
    state: MemberListState,
    onQuery: (String) -> Unit,
    onMore: () -> Unit,
    modifier: Modifier = Modifier,
    maxHeight: Dp = 320.dp,
    onOpen: ((ChatPerson) -> Unit)? = null,
    presence: (ChatPerson) -> String? = { null },
) {
    Column(modifier.fillMaxWidth()) {
        if (state.members.size > 1 || state.isSearch || state.hasMore) MemberSearchField(state.query, onQuery)
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = maxHeight)) {
            items(state.visible, key = { it.id }) { person ->
                MemberRow(person, presence(person), modifier = if (onOpen == null) Modifier else Modifier.clickable { onOpen(person) })
            }
            memberListTail(state, onMore)
        }
    }
}
