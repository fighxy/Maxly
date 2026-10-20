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
import app.maxly.presentation.contacts.PendingUndo
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/**
 * Диалоги действий с контактом: «Изменить контакт», подтверждение удаления, добавление по номеру.
 * Итог уходит в [onNotice] (снекбар экрана). После удаления [snackbar] показывает «Контакт
 * удалён» с «Отменить». [fullScreenEdit] — форма изменения на весь экран (телефон), иначе окном.
 */
@Composable
fun ContactActionsHost(
    actions: ContactActions,
    snackbar: SnackbarHostState,
    onNotice: (String) -> Unit,
    fullScreenEdit: Boolean = false,
) {
    val state by actions.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.notice) {
        val text = state.notice ?: return@LaunchedEffect
        onNotice(text)
        actions.consumeNotice()
    }
    val undo = state.undo
    // Новое удаление меняет token: прошлый снекбар закрывается, его удаление уже окончательное.
    LaunchedEffect(undo?.token) {
        val pending = undo ?: return@LaunchedEffect
        val result = snackbar.showSnackbar(PendingUndo.TEXT, PendingUndo.ACTION, withDismissAction = false, duration = SnackbarDuration.Long)
        if (result == SnackbarResult.ActionPerformed) actions.undo(pending.token) else actions.finishUndo(pending.token)
    }
    when (val dialog = state.dialog) {
        is ContactDialog.Rename -> ContactEditForm(
            initialFirst = dialog.firstName,
            initialLast = dialog.lastName,
            busy = state.busy,
            error = state.error,
            fullScreen = fullScreenEdit,
            onDone = actions::rename,
            onDismiss = actions::dismiss,
        )
        is ContactDialog.Remove -> AlertDialog(
            onDismissRequest = actions::dismiss,
            title = { Text("Удалить „${dialog.name}“ из контактов?") },
            text = {
                Column {
                    Text("Переписка сохранится.")
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

/** Подпись под полями «Изменить контакт». */
const val CONTACT_EDIT_CAPTION = "Имя сохранится в вашем аккаунте MAX. Человек его не увидит. " +
    "Чтобы вернуть имя, которое указал человек, очистите оба поля."

/**
 * «Изменить контакт»: своё имя контакта, «Отмена» и «Готово». [fullScreen] — на весь экран,
 * иначе окно поверх экрана.
 */
@Composable
fun ContactEditForm(
    initialFirst: String,
    initialLast: String,
    busy: Boolean,
    error: String?,
    fullScreen: Boolean,
    onDone: (String, String) -> Unit,
    onDismiss: () -> Unit,
) {
    var first by remember { mutableStateOf(initialFirst.take(ContactNameRules.MAX)) }
    var last by remember { mutableStateOf(initialLast.take(ContactNameRules.MAX)) }
    Dialog(
        onDismissRequest = { if (!busy) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = !fullScreen),
    ) {
        Surface(
            shape = if (fullScreen) RectangleShape else RoundedCornerShape(24.dp),
            color = MaterialTheme.colorScheme.surface,
            modifier = if (fullScreen) Modifier.fillMaxSize() else Modifier.widthIn(min = 360.dp, max = 480.dp),
        ) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Row(Modifier.fillMaxWidth().height(56.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onDismiss, enabled = !busy) { Text("Отмена") }
                    Text(
                        "Изменить контакт",
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = { onDone(first, last) }, enabled = !busy) { Text("Готово") }
                }
                Spacer(Modifier.height(8.dp))
                NameFields(first, last, { first = it }, { last = it })
                Spacer(Modifier.height(4.dp))
                Text(
                    CONTACT_EDIT_CAPTION,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                error?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
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

/** «⋮» у строки контакта: те же «Изменить» и «Удалить из контактов», что в профиле. */
@Composable
fun ContactRowMenu(onRename: () -> Unit, onRemove: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Default.MoreVert, "Действия с контактом") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text("Изменить") }, onClick = { open = false; onRename() })
            DropdownMenuItem(text = { Text("Удалить из контактов") }, onClick = { open = false; onRemove() })
        }
    }
}

private const val PHONE_MAX = 32
