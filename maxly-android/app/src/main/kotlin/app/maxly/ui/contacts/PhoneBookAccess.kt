package app.maxly.ui.contacts

// Вход «Найти друзей из контактов»: пояснение перед системным запросом разрешения,
// отказ и отказ насовсем (кнопка в настройки приложения). Логика — PhoneBookViewModel.

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Contacts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import app.maxly.presentation.contacts.PhoneBookPrompt
import app.maxly.presentation.contacts.PhoneBookUiState
import app.maxly.presentation.contacts.PhoneBookViewModel

private const val PERMISSION = Manifest.permission.READ_CONTACTS

/**
 * Невидимая часть доступа к книге: сверка разрешения при каждом возврате на экран (его могли
 * дать или забрать в настройках), системный запрос и окна пояснения и отказа. Сам ничего
 * не спрашивает: всё начинается с нажатия на [PhoneBookRow].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PhoneBookAccess(model: PhoneBookViewModel) {
    val context = LocalContext.current
    val state by model.state.collectAsStateWithLifecycle()
    if (!state.isAvailable) return
    val granted = { ContextCompat.checkSelfPermission(context, PERMISSION) == PackageManager.PERMISSION_GRANTED }
    val canAskAgain = { context.findActivity()?.let { ActivityCompat.shouldShowRequestPermissionRationale(it, PERMISSION) } ?: false }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        model.permissionResult(ok, canAskAgain())
    }
    val ask = {
        model.systemPromptShown()
        launcher.launch(PERMISSION)
    }
    val lifecycle = LocalLifecycleOwner.current
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { model.permissionChecked(granted(), canAskAgain()) }
    }
    when (state.prompt) {
        PhoneBookPrompt.RATIONALE -> ModalBottomSheet(
            onDismissRequest = model::dismissPrompt,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.Contacts, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.size(12.dp))
                Text("Найти друзей из контактов", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.size(8.dp))
                Text(
                    "Maxly прочитает имена и номера из телефонной книги, чтобы найти среди них знакомых. " +
                        "Книга читается только на этом телефоне и никуда не отправляется. " +
                        "Доступ можно забрать в любой момент в настройках Android.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(20.dp))
                Button(onClick = ask, modifier = Modifier.fillMaxWidth()) { Text("Продолжить") }
                TextButton(onClick = model::dismissPrompt, modifier = Modifier.fillMaxWidth()) { Text("Не сейчас") }
                Spacer(Modifier.size(12.dp))
            }
        }
        PhoneBookPrompt.DENIED -> AlertDialog(
            onDismissRequest = model::dismissPrompt,
            title = { Text("Нет доступа к контактам") },
            text = { Text("Без доступа к телефонной книге найти знакомых не получится. Разрешить можно сейчас или позже.") },
            confirmButton = { TextButton(onClick = ask) { Text("Разрешить") } },
            dismissButton = { TextButton(onClick = model::dismissPrompt) { Text("Не сейчас") } },
        )
        PhoneBookPrompt.BLOCKED -> AlertDialog(
            onDismissRequest = model::dismissPrompt,
            title = { Text("Доступ к контактам запрещён") },
            text = { Text("Android больше не спрашивает разрешение. Включите его в настройках приложения: «Разрешения» → «Контакты».") },
            confirmButton = {
                TextButton(onClick = {
                    model.openedSettings()
                    context.openAppSettings()
                }) { Text("Открыть настройки") }
            },
            dismissButton = { TextButton(onClick = model::dismissPrompt) { Text("Отмена") } },
        )
        null -> Unit
    }
}

/** Строка «Найти друзей из контактов» над списком контактов. */
@Composable
internal fun PhoneBookRow(state: PhoneBookUiState, onClick: () -> Unit, onRefresh: () -> Unit) {
    ListItem(
        leadingContent = { Icon(Icons.Outlined.Contacts, null, tint = MaterialTheme.colorScheme.primary) },
        headlineContent = { Text("Найти друзей из контактов", color = MaterialTheme.colorScheme.primary) },
        supportingContent = { Text(state.summary, maxLines = 2) },
        trailingContent = when {
            state.isLoading -> ({ CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) })
            state.entryCount != null -> ({
                IconButton(onClick = onRefresh) { Icon(Icons.Filled.Refresh, "Прочитать книгу заново") }
            })
            else -> null
        },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        modifier = Modifier.clickable(enabled = !state.isLoading, onClick = onClick),
    )
}

private fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

private fun Context.openAppSettings() {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { startActivity(intent) }
}
