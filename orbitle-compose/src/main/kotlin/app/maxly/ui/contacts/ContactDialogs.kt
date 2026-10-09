package app.maxly.ui.contacts

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.contacts.ContactActions
import app.maxly.presentation.contacts.ContactDialog
import app.maxly.presentation.contacts.ContactNameRules

/**
 * Диалоги действий с контактом: переименование, подтверждение удаления, добавление по номеру.
 * Итог уходит в [onNotice] (снекбар экрана).
 */
@Composable
fun ContactActionsHost(actions: ContactActions, onNotice: (String) -> Unit) {
    val state by actions.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.notice) {
        val text = state.notice ?: return@LaunchedEffect
        onNotice(text)
        actions.consumeNotice()
    }
    when (val dialog = state.dialog) {
        is ContactDialog.Rename -> ContactNameDialog(
            title = "Имя контакта",
            initialFirst = dialog.firstName,
            initialLast = dialog.lastName,
            busy = state.busy,
            error = state.error,
            onDone = actions::rename,
            onDismiss = actions::dismiss,
        )
        is ContactDialog.Remove -> AlertDialog(
            onDismissRequest = actions::dismiss,
            title = { Text("Удалить из контактов?") },
            text = {
                Column {
                    Text("${dialog.name} пропадёт из контактов. Переписка останется.")
                    state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            },
            confirmButton = {
                TextButton(onClick = actions::remove, enabled = !state.busy) { Text("Удалить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = actions::dismiss, enabled = !state.busy) { Text("Отмена") } },
        )
        ContactDialog.AddByPhone -> AddByPhoneDialog(state.busy, state.error, actions::addByPhone, actions::dismiss)
        null -> Unit
    }
}

/** Имя и фамилия контакта, каждое не длиннее [ContactNameRules.MAX]. */
@Composable
fun ContactNameDialog(
    title: String,
    initialFirst: String,
    initialLast: String,
    busy: Boolean,
    error: String?,
    onDone: (String, String) -> Unit,
    onDismiss: () -> Unit,
) {
    var first by remember { mutableStateOf(initialFirst.take(ContactNameRules.MAX)) }
    var last by remember { mutableStateOf(initialLast.take(ContactNameRules.MAX)) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                NameFields(first, last, { first = it }, { last = it })
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = { onDone(first, last) }, enabled = !busy) { Text("Сохранить") } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Отмена") } },
    )
}

@Composable
private fun AddByPhoneDialog(busy: Boolean, error: String?, onDone: (String, String, String) -> Unit, onDismiss: () -> Unit) {
    var phone by remember { mutableStateOf("") }
    var first by remember { mutableStateOf("") }
    var last by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Новый контакт") },
        text = {
            Column {
                OutlinedTextField(
                    value = phone,
                    onValueChange = { phone = it.take(PHONE_MAX) },
                    label = { Text("Номер телефона") },
                    placeholder = { Text("+7 900 000-00-00") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                NameFields(first, last, { first = it }, { last = it })
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = { onDone(phone, first, last) }, enabled = !busy && phone.isNotBlank()) { Text("Добавить") } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("Отмена") } },
    )
}

@Composable
private fun NameFields(first: String, last: String, onFirst: (String) -> Unit, onLast: (String) -> Unit) {
    OutlinedTextField(
        value = first,
        onValueChange = { onFirst(it.take(ContactNameRules.MAX)) },
        label = { Text("Имя") },
        supportingText = { Text("${first.length} / ${ContactNameRules.MAX}") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    OutlinedTextField(
        value = last,
        onValueChange = { onLast(it.take(ContactNameRules.MAX)) },
        label = { Text("Фамилия") },
        supportingText = { Text("${last.length} / ${ContactNameRules.MAX}") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}

/** «⋮» у строки контакта: переименовать или удалить. */
@Composable
fun ContactRowMenu(onRename: () -> Unit, onRemove: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Default.MoreVert, "Действия с контактом") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("Переименовать") }, onClick = { open = false; onRename() })
            DropdownMenuItem(text = { Text("Удалить из контактов") }, onClick = { open = false; onRemove() })
        }
    }
}

private const val PHONE_MAX = 32
