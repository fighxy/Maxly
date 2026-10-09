package app.maxly.ui.chat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import app.maxly.ui.components.AppSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.data.BotCommandRow
import app.maxly.data.ChatMemberRow
import app.maxly.domain.ChatType
import app.maxly.presentation.chat.ChatViewModel
import app.maxly.presentation.chat.ComposerHints
import app.maxly.presentation.chat.ScheduleWhen
import java.time.Instant
import java.time.ZoneId

/**
 * Плашка закрепа над лентой. Касание переходит к показанному сообщению и листает к следующему
 * закрепу; крестик снимает показанный, «Все» — все закрепы чата.
 */
@Composable
fun PinBanner(
    title: String,
    text: String,
    count: Int,
    onOpen: () -> Unit,
    onUnpin: () -> Unit,
    onUnpinAll: () -> Unit,
) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
        Row(
            Modifier.clickable(onClick = onOpen).padding(start = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.PushPin, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
            androidx.compose.foundation.layout.Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                Text(
                    title,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (count > 1) {
                androidx.compose.material3.TextButton(onClick = onUnpinAll) { Text("Открепить все") }
            }
            IconButton(onClick = onUnpin) { Icon(Icons.Filled.Close, "Открепить") }
        }
    }
}

/** Подсказки `@` и `/` над полем ввода. */
@Composable
fun ComposerHintsBar(
    hints: ComposerHints,
    onMention: (ChatMemberRow) -> Unit,
    onCommand: (BotCommandRow) -> Unit,
) {
    if (hints.mentions.isEmpty() && hints.commands.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
        hints.mentions.forEach { member ->
            Text(
                "@${member.name}",
                modifier = Modifier.fillMaxWidth().clickable { onMention(member) }.padding(vertical = 6.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        hints.commands.forEach { command ->
            val name = command.name.trim().removePrefix("/")
            Text(
                if (command.description.isBlank()) "/$name" else "/$name — ${command.description}",
                modifier = Modifier.fillMaxWidth().clickable { onCommand(command) }.padding(vertical = 6.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InChatSearchSheet(model: ChatViewModel, onHit: (String) -> Unit, onDismiss: () -> Unit) {
    val search by model.search.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf(search.query) }
    AppSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Поиск в чате") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { model.searchInside(query) }),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { model.searchInside(query) },
                enabled = !search.busy,
                modifier = Modifier.padding(top = 12.dp),
            ) { Text("Найти") }
            if (search.busy) {
                CircularProgressIndicator(Modifier.padding(top = 16.dp).size(22.dp), strokeWidth = 2.dp)
            }
            search.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
            }
            if (!search.busy && search.query.isNotBlank() && search.hits.isEmpty() && search.error == null) {
                Text("Ничего не нашлось", modifier = Modifier.padding(top = 12.dp))
            }
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp).padding(top = 8.dp)) {
                items(search.hits, key = { "${it.chatId}:${it.messageId}" }) { hit ->
                    ListItem(
                        headlineContent = { Text(hit.text.ifBlank { "Сообщение" }, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        supportingContent = hit.senderName?.let { name -> { Text(name) } },
                        modifier = Modifier.clickable {
                            onDismiss()
                            onHit(hit.messageId)
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatToolsSheet(
    model: ChatViewModel,
    onCall: () -> Unit,
    onDeleteChat: () -> Unit,
    onClearHistory: () -> Unit,
    onDismiss: () -> Unit,
) {
    val tools by model.tools.collectAsStateWithLifecycle()
    val header = model.state.collectAsStateWithLifecycle().value.header
    val canCall = header != null && header.type == ChatType.PRIVATE && !header.isSavedMessages
    AppSheet(onDismissRequest = onDismiss, wide = true) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("О чате", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                if (tools.busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            }
            tools.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = 8.dp))
            }
            tools.notice?.let {
                Text(it, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp))
            }
            model.memberList?.let { list ->
                val people by list.state.collectAsStateWithLifecycle()
                SectionTitle("Участники")
                app.maxly.ui.profile.MemberListBlock(people, onQuery = list::search, onMore = list::loadMore, presence = model::memberPresence)
            }
            SectionTitle("Общие чаты")
            if (tools.shared.isEmpty()) {
                Text("Общих чатов нет", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                tools.shared.forEach { chat ->
                    Text(chat.title, modifier = Modifier.padding(vertical = 4.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (canCall) {
                ListItem(
                    headlineContent = { Text("Позвонить") },
                    supportingContent = { Text("Сервер получит сигнал. Звук и видео этот клиент не передаёт.") },
                    modifier = Modifier.clickable(enabled = !tools.busy, onClick = onCall),
                )
            }
            if (tools.reasons.isNotEmpty()) {
                SectionTitle("Пожаловаться")
                tools.reasons.forEach { reason ->
                    Text(
                        reason.title.ifBlank { "Причина ${reason.id}" },
                        modifier = Modifier.fillMaxWidth().clickable(enabled = !tools.busy) { model.complain(reason.id) }.padding(vertical = 8.dp),
                    )
                }
            }
            ListItem(
                headlineContent = { Text("Очистить историю") },
                supportingContent = { Text("Сообщения пропадут. Сам чат останется.") },
                modifier = Modifier.clickable(enabled = !tools.busy, onClick = onClearHistory),
            )
            ListItem(
                headlineContent = { Text("Удалить чат", color = MaterialTheme.colorScheme.error) },
                supportingContent = { Text("Чат пропадёт из списка вместе с перепиской.") },
                modifier = Modifier.clickable(enabled = !tools.busy, onClick = onDeleteChat),
            )
        }
    }
}

/** Удаление чата или очистка переписки: только у себя или у всех. */
enum class ChatErase { DELETE, CLEAR }

/** Действие с чатом, выбранное в его профиле: поиск, «О чате», звонок, очистка, удаление. */
enum class ChatAction { SEARCH, TOOLS, CALL, CLEAR_HISTORY, DELETE_CHAT, LEAVE, JOIN }

@Composable
fun EraseChatDialog(
    kind: ChatErase,
    type: app.maxly.domain.ChatType,
    saved: Boolean,
    title: String,
    onChoose: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    val mine = when (kind) {
        ChatErase.CLEAR -> if (saved) "Очистить" else "Очистить только у меня"
        ChatErase.DELETE -> if (saved) "Удалить" else "Удалить только у меня"
    }
    val everyone = when (kind) {
        ChatErase.CLEAR -> if (type == app.maxly.domain.ChatType.PRIVATE) "Очистить у меня и у собеседника" else "Очистить у всех"
        ChatErase.DELETE -> if (type == app.maxly.domain.ChatType.PRIVATE) "Удалить у меня и у собеседника" else "Удалить у всех"
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (kind == ChatErase.CLEAR) "Очистить историю?" else "Удалить чат «$title»?") },
        text = {
            Text(
                if (kind == ChatErase.CLEAR) {
                    "Все сообщения в этом чате будут удалены без возможности восстановления."
                } else {
                    "Чат будет удалён вместе со всей перепиской."
                },
            )
        },
        confirmButton = {
            Row {
                TextButton(onClick = { onChoose(false) }) { Text(mine) }
                if (!saved) {
                    Spacer(Modifier.width(8.dp))
                    TextButton(onClick = { onChoose(true) }) {
                        Text(everyone, color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        modifier = Modifier.padding(top = 16.dp, bottom = 4.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollComposerSheet(onSend: (String, List<String>) -> Unit, onDismiss: () -> Unit) {
    var title by remember { mutableStateOf("") }
    var answers by remember { mutableStateOf(listOf("", "")) }
    var error by remember { mutableStateOf<String?>(null) }
    AppSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text("Опрос", style = MaterialTheme.typography.titleLarge)
            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                label = { Text("Вопрос") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            )
            answers.forEachIndexed { index, answer ->
                OutlinedTextField(
                    value = answer,
                    onValueChange = { value -> answers = answers.toMutableList().also { it[index] = value } },
                    label = { Text("Ответ ${index + 1}") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
            }
            if (answers.size < 10) {
                TextButton(onClick = { answers = answers + "" }) { Text("Ещё ответ") }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Button(
                onClick = {
                    val clean = answers.map { it.trim() }.filter { it.isNotEmpty() }
                    if (title.trim().isEmpty() || clean.size < 2) {
                        error = "Нужны вопрос и два ответа"
                    } else {
                        onSend(title.trim(), clean)
                        onDismiss()
                    }
                },
                modifier = Modifier.padding(top = 8.dp),
            ) { Text("Отправить опрос") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleSheet(model: ChatViewModel, onDismiss: () -> Unit) {
    val draft = model.state.collectAsStateWithLifecycle().value.draft
    val scheduled by model.scheduled.collectAsStateWithLifecycle()
    var picking by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<app.maxly.domain.ScheduledMessage?>(null) }
    LaunchedEffect(Unit) { model.loadScheduled() }
    AppSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp)
                .verticalScroll(androidx.compose.foundation.rememberScrollState()),
        ) {
            Text("Отложить", style = MaterialTheme.typography.titleLarge)
            Text(
                draft.trim().ifBlank { "В поле нет текста" },
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
            if (draft.isNotBlank()) {
                ListItem(
                    headlineContent = { Text("Через час") },
                    modifier = Modifier.clickable {
                        model.scheduleAt(draft, ScheduleWhen.inOneHour(System.currentTimeMillis()))
                        onDismiss()
                    },
                )
                ListItem(
                    headlineContent = { Text("Завтра в 9:00") },
                    modifier = Modifier.clickable {
                        model.scheduleAt(draft, ScheduleWhen.tomorrowAtNine(System.currentTimeMillis(), ZoneId.systemDefault()))
                        onDismiss()
                    },
                )
                if (picking) {
                    ScheduleTimePicker(null, confirm = "Отложить") { at ->
                        model.scheduleAt(draft, at)
                        onDismiss()
                    }
                } else {
                    ListItem(
                        headlineContent = { Text("Выбрать дату и время…") },
                        modifier = Modifier.clickable { picking = true },
                    )
                }
            }
            if (scheduled.isNotEmpty()) {
                SectionTitle("Уже отложено")
                scheduled.forEach { item ->
                    ListItem(
                        headlineContent = { Text(item.text.ifBlank { "Сообщение" }, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        supportingContent = {
                            val time = item.sendAt?.let(::formatWhen).orEmpty().ifBlank { "Время не указано" }
                            Text(
                                if (item.failed) "$time — не отправилось" else time,
                                color = if (item.failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        trailingContent = {
                            Row {
                                TextButton(onClick = { editing = item }) { Text("Изменить") }
                                TextButton(onClick = { model.cancelScheduled(item) }) { Text("Отменить") }
                            }
                        },
                    )
                }
            }
            Spacer(Modifier.size(8.dp))
        }
    }
    editing?.let { item ->
        var text by remember(item.id) { mutableStateOf(item.text) }
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text("Изменить отложенное") },
            text = {
                Column {
                    OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth(), label = { Text("Текст") })
                    ScheduleTimePicker(item.sendAt, confirm = "Сохранить") { at ->
                        model.editScheduled(item, text, at)
                        editing = null
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { editing = null }) { Text("Отмена") } },
        )
    }
}

/** Ручной выбор времени: день из ближайшей недели, час и минута кнопками. */
@Composable
private fun ScheduleTimePicker(initialMs: Long?, confirm: String, onPicked: (Long) -> Unit) {
    val zone = ZoneId.systemDefault()
    val now = remember { System.currentTimeMillis() }
    var choice by remember(initialMs) { mutableStateOf(ScheduleWhen.initial(initialMs, now, zone)) }
    val days = remember { ScheduleWhen.days(now, zone) }
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Row(Modifier.fillMaxWidth().horizontalScroll(androidx.compose.foundation.rememberScrollState())) {
            days.forEach { day ->
                androidx.compose.material3.FilterChip(
                    selected = day == choice.day,
                    onClick = { choice = choice.copy(day = day) },
                    label = { Text(ScheduleWhen.dayLabel(day, days.first())) },
                    modifier = Modifier.padding(end = 6.dp),
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
            TextButton(onClick = { choice = ScheduleWhen.shift(choice, hours = -1) }) { Text("−1 ч") }
            TextButton(onClick = { choice = ScheduleWhen.shift(choice, minutes = -5) }) { Text("−5 мин") }
            Text(choice.clock, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 8.dp))
            TextButton(onClick = { choice = ScheduleWhen.shift(choice, minutes = 5) }) { Text("+5 мин") }
            TextButton(onClick = { choice = ScheduleWhen.shift(choice, hours = 1) }) { Text("+1 ч") }
        }
        val at = choice.toMillis(zone)
        val future = at > System.currentTimeMillis()
        Button(onClick = { onPicked(at) }, enabled = future) { Text(confirm) }
        if (!future) {
            Text("Это время уже прошло", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
fun CallConfirmDialog(onAudio: () -> Unit, onVideo: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Позвонить?") },
        text = { Text("Сервер получит сигнал звонка. Звук и видео этот клиент не передаёт.") },
        confirmButton = {
            Row {
                TextButton(onClick = onAudio) { Text("Аудио") }
                Spacer(Modifier.width(8.dp))
                TextButton(onClick = onVideo) { Text("Видео") }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

private fun formatWhen(timeMs: Long): String {
    if (timeMs <= 0L) return ""
    val zoned = Instant.ofEpochMilli(timeMs).atZone(ZoneId.systemDefault())
    return "%02d.%02d %02d:%02d".format(zoned.dayOfMonth, zoned.monthValue, zoned.hour, zoned.minute)
}
