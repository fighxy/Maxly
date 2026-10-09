package app.maxly.ui.chatlist

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import app.maxly.ui.components.AppSheet
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.maxly.domain.Contact
import app.maxly.presentation.chatlist.NewChatModel
import app.maxly.presentation.chatlist.NewChatStep
import app.maxly.presentation.chatlist.NewChatUiState

/** Лист с кнопки «Новое сообщение»: контакт, номер, группа, канал. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewChatSheet(state: NewChatUiState, model: NewChatModel) {
    AppSheet(onDismissRequest = model::dismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (state.step != NewChatStep.MENU) {
                    IconButton(onClick = model::back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") }
                }
                Text(stepTitle(state.step), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                if (state.busy) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                }
            }
            state.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
            }
            state.notice?.let {
                Text(it, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
            }
            when (state.step) {
                NewChatStep.MENU -> Menu(model)
                NewChatStep.CONTACT -> People(state, model)
                NewChatStep.PHONE -> Phone(state, model)
                NewChatStep.GROUP -> Group(state, model)
                NewChatStep.CHANNEL -> Channel(state, model)
                NewChatStep.LINK -> Link(state, model)
            }
        }
    }
}

@Composable
private fun Menu(model: NewChatModel) {
    MenuRow("Написать контакту", "Выбрать из списка") { model.open(NewChatStep.CONTACT) }
    MenuRow("Написать новому", "Найти по номеру телефона") { model.open(NewChatStep.PHONE) }
    MenuRow("Создать группу", "Название и участники") { model.open(NewChatStep.GROUP) }
    MenuRow("Создать канал", "Только название") { model.open(NewChatStep.CHANNEL) }
    MenuRow("Открыть по ссылке", "Приглашение в группу или канал") { model.open(NewChatStep.LINK) }
}

@Composable
private fun MenuRow(title: String, subtitle: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        modifier = Modifier.clickable(onClick = onClick).fillMaxWidth(),
    )
}

@Composable
private fun People(state: NewChatUiState, model: NewChatModel) {
    QueryField(state, model)
    val shown = matching(state)
    if (shown.isEmpty()) {
        Text(if (state.query.isBlank()) "Контактов пока нет" else "Никого не нашлось", modifier = Modifier.padding(top = 12.dp))
        return
    }
    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp).padding(top = 8.dp)) {
        items(shown, key = { it.id }) { person ->
            ListItem(
                headlineContent = { Text(person.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                supportingContent = person.phone.takeIf { it.isNotBlank() }?.let { phone -> { Text(phone) } },
                modifier = Modifier.clickable(enabled = !state.busy) { model.writeTo(person.id, person.displayName) },
            )
        }
    }
}

@Composable
private fun QueryField(state: NewChatUiState, model: NewChatModel) {
    OutlinedTextField(
        value = state.query,
        onValueChange = model::setQuery,
        label = { Text("Имя или номер") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )
}

@Composable
private fun Phone(state: NewChatUiState, model: NewChatModel) {
    OutlinedTextField(
        value = state.phone,
        onValueChange = model::setPhone,
        label = { Text("Номер телефона") },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { model.lookup() }),
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )
    Button(
        onClick = model::lookup,
        enabled = !state.busy,
        modifier = Modifier.padding(top = 12.dp),
    ) { Text("Найти") }
    val person = state.found
    if (person != null) {
        ListItem(
            headlineContent = { Text(person.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            supportingContent = { Text(person.phone) },
            modifier = Modifier.padding(top = 8.dp),
        )
        if (!person.added) {
            OutlinedTextField(
                value = state.contactName,
                onValueChange = model::setContactName,
                label = { Text("Имя в контактах") },
                supportingText = { Text("Можно оставить пустым") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
            Button(onClick = model::writeFound, enabled = !state.busy) { Text("Написать") }
            if (person.added) {
                Text("В контактах", modifier = Modifier.align(Alignment.CenterVertically))
            } else {
                TextButton(onClick = model::addFound, enabled = !state.busy) { Text("Добавить в контакты") }
            }
        }
    }
}

@Composable
private fun Group(state: NewChatUiState, model: NewChatModel) {
    TitleField(state, model)
    QueryField(state, model)
    Text(
        "Участников можно не выбирать.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp),
    )
    MemberList(state, model)
    Button(
        onClick = model::createGroup,
        enabled = !state.busy,
        modifier = Modifier.padding(top = 12.dp),
    ) { Text("Создать группу") }
}

@Composable
private fun Link(state: NewChatUiState, model: NewChatModel) {
    OutlinedTextField(
        value = state.link,
        onValueChange = model::setLink,
        label = { Text("Ссылка или код приглашения") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )
    Button(
        onClick = model::joinLink,
        enabled = !state.busy,
        modifier = Modifier.padding(top = 12.dp),
    ) { Text("Открыть") }
}

@Composable
private fun Channel(state: NewChatUiState, model: NewChatModel) {
    TitleField(state, model)
    Button(
        onClick = model::createChannel,
        enabled = !state.busy,
        modifier = Modifier.padding(top = 12.dp),
    ) { Text("Создать канал") }
}

@Composable
private fun TitleField(state: NewChatUiState, model: NewChatModel) {
    OutlinedTextField(
        value = state.title,
        onValueChange = model::setTitle,
        label = { Text("Название") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )
}

@Composable
private fun MemberList(state: NewChatUiState, model: NewChatModel) {
    val shown = matching(state)
    if (shown.isEmpty()) {
        Text(if (state.query.isBlank()) "Контактов пока нет" else "Никого не нашлось", modifier = Modifier.padding(top = 12.dp))
        return
    }
    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 280.dp).padding(top = 8.dp)) {
        items(shown, key = { it.id }) { person ->
            Row(
                Modifier.fillMaxWidth().clickable { model.toggleMember(person.id) }.padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(checked = person.id in state.selected, onCheckedChange = null)
                Spacer(Modifier.width(8.dp))
                Column {
                    Text(person.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (person.phone.isNotBlank()) {
                        Text(person.phone, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private fun matching(state: NewChatUiState): List<Contact> {
    val query = state.query.trim()
    if (query.isEmpty()) return state.people
    val digits = query.filter { it.isDigit() }
    return state.people.filter { person ->
        person.displayName.contains(query, ignoreCase = true) || (digits.length >= 3 && person.phone.contains(digits))
    }
}

private fun stepTitle(step: NewChatStep): String = when (step) {
    NewChatStep.MENU -> "Новое сообщение"
    NewChatStep.CONTACT -> "Контакт"
    NewChatStep.PHONE -> "Новый человек"
    NewChatStep.GROUP -> "Новая группа"
    NewChatStep.CHANNEL -> "Новый канал"
    NewChatStep.LINK -> "Ссылка"
}
