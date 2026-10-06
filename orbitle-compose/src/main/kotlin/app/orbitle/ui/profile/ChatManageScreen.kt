package app.orbitle.ui.profile

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.data.ChatPerson
import app.orbitle.data.GroupOption
import app.orbitle.presentation.profile.ChatManageViewModel

/** Управление группой или каналом: карточка, ссылка, права, участники и заявки. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatManageScreen(
    model: ChatManageViewModel,
    contacts: List<ChatPerson>,
    onBack: () -> Unit,
    onPickPhoto: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    var picking by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(state.message) {
        val text = state.message ?: return@LaunchedEffect
        snackbar.showSnackbar(text)
        model.dismissMessage()
    }
    if (picking) {
        val already = state.members.map { it.id }.toSet()
        val choices = contacts.filter { it.id !in already }
        AlertDialog(
            onDismissRequest = { picking = false },
            title = { Text(if (state.isChannel) "Добавить подписчика" else "Добавить участника") },
            text = {
                if (choices.isEmpty()) Text("В контактах никого больше нет")
                else LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    items(choices, key = { it.id }) { person ->
                        Text(person.name, modifier = Modifier.fillMaxWidth().clickable {
                            picking = false
                            model.addMember(person.id)
                        }.padding(vertical = 8.dp))
                    }
                }
            },
            confirmButton = { TextButton(onClick = { picking = false }) { Text("Закрыть") } },
        )
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Управление") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize().padding(horizontal = 16.dp)) {
            item {
                OutlinedTextField(state.title, model::editTitle, label = { Text("Название") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(state.description, model::editDescription, label = { Text("Описание") }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = model::saveCard, enabled = !state.busy) { Text("Сохранить") }
                    TextButton(onClick = onPickPhoto, enabled = !state.busy) { Text("Фото") }
                }
            }
            item { Section("Ссылка-приглашение") }
            item {
                val link = state.link
                if (link == null) Text("Сервер не прислал ссылку. Её можно перевыпустить.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                else {
                    val clipboard = LocalClipboardManager.current
                    Text(link, color = MaterialTheme.colorScheme.primary, modifier = Modifier.clickable {
                        clipboard.setText(AnnotatedString(link))
                    })
                    QrModules(state.qr)
                }
                TextButton(onClick = model::revokeLink, enabled = !state.busy) { Text("Перевыпустить ссылку") }
            }
            if (state.isChannel && state.commentsEnabled != null) {
                item {
                    Toggle("Комментарии", state.commentsEnabled == true, state.busy) { model.setComments(it) }
                }
            }
            item { Section("Права") }
            item { Toggle("Только владелец меняет название и фото", state.onlyOwnerRenames, state.busy) { model.setOption(GroupOption.ONLY_OWNER_RENAMES, it) } }
            item { Toggle("Все могут закреплять", state.allCanPin, state.busy) { model.setOption(GroupOption.ALL_CAN_PIN, it) } }
            item { Toggle("Участников добавляет только админ", state.onlyAdminAdds, state.busy) { model.setOption(GroupOption.ONLY_ADMIN_ADDS, it) } }
            item { Toggle("Звонить может только админ", state.onlyAdminCalls, state.busy) { model.setOption(GroupOption.ONLY_ADMIN_CALLS, it) } }
            item { Toggle("Участники видят ссылку", state.membersSeeLink, state.busy) { model.setOption(GroupOption.MEMBERS_SEE_LINK, it) } }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Section(if (state.isChannel) "Подписчики" else "Участники")
                    TextButton(onClick = { picking = true }, enabled = !state.busy) { Text("Добавить") }
                }
            }
            items(state.members, key = { it.id }) { person ->
                MemberRow(person, state.busy, onAdmin = { model.setAdmin(person.id, person.role != ChatPerson.Role.ADMIN) }, onRemove = { model.removeMember(person.id) })
            }
            if (state.requests.isNotEmpty()) {
                item { Section("Заявки") }
                items(state.requests, key = { "req-${it.id}" }) { person ->
                    ListItem(
                        headlineContent = { Text(person.name) },
                        trailingContent = {
                            Row {
                                TextButton(onClick = { model.decideRequest(person.id, true) }, enabled = !state.busy) { Text("Принять") }
                                TextButton(onClick = { model.decideRequest(person.id, false) }, enabled = !state.busy) { Text("Отклонить") }
                            }
                        },
                    )
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
        if (state.busy) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
}

@Composable
private fun Toggle(title: String, checked: Boolean, busy: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, enabled = !busy)
    }
}

@Composable
private fun MemberRow(person: ChatPerson, busy: Boolean, onAdmin: () -> Unit, onRemove: () -> Unit) {
    val role = when (person.role) {
        ChatPerson.Role.OWNER -> "владелец"
        ChatPerson.Role.ADMIN -> "админ"
        ChatPerson.Role.MEMBER -> ""
    }
    ListItem(
        headlineContent = { Text(person.name) },
        supportingContent = if (role.isEmpty()) null else ({ Text(role) }),
        trailingContent = {
            if (person.role != ChatPerson.Role.OWNER) {
                Row {
                    TextButton(onClick = onAdmin, enabled = !busy) {
                        Text(if (person.role == ChatPerson.Role.ADMIN) "Снять" else "Админ")
                    }
                    TextButton(onClick = onRemove, enabled = !busy) { Text("Удалить") }
                }
            }
        },
    )
}

@Composable
private fun QrModules(modules: List<BooleanArray>) {
    if (modules.isEmpty()) return
    Box(Modifier.padding(top = 8.dp).clip(RoundedCornerShape(12.dp)).background(Color.White).padding(8.dp)) {
        Canvas(Modifier.size(160.dp)) {
            val cell = size.width / modules.size
            modules.forEachIndexed { y, row ->
                row.forEachIndexed { x, dark ->
                    if (dark) drawRect(Color.Black, Offset(x * cell, y * cell), Size(cell + 0.5f, cell + 0.5f))
                }
            }
        }
    }
}
