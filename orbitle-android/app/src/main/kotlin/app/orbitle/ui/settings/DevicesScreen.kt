package app.orbitle.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.orbitle.data.DeviceSession
import app.orbitle.data.SessionRepository
import app.orbitle.domain.OrbitleError
import app.orbitle.presentation.common.PresenceText
import kotlinx.coroutines.launch

/** «Устройства»: сеансы аккаунта, текущий сверху, и «Завершить другие сеансы». */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DevicesScreen(repository: SessionRepository, onBack: () -> Unit) {
    var sessions by remember { mutableStateOf<List<DeviceSession>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirm by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val presence = remember { PresenceText() }
    suspend fun load() {
        try {
            sessions = repository.sessions()
            error = null
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            error = (e as? OrbitleError)?.userMessage ?: OrbitleError.Unknown.userMessage
            if (sessions == null) sessions = emptyList()
        }
    }
    LaunchedEffect(Unit) { load() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Устройства") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        val list = sessions
        if (list == null) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            error?.let { item { Text(it, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) } }
            items(list, key = { it.id }) { session ->
                val status = when {
                    session.isCurrent -> "это устройство"
                    session.lastActiveMs > 0 -> presence.status(false, session.lastActiveMs, System.currentTimeMillis()).replace("был(а)", "активен")
                    else -> null
                }
                ListItem(
                    leadingContent = { Icon(if (session.isCurrent) Icons.Outlined.PhoneAndroid else Icons.Outlined.Devices, null) },
                    headlineContent = { Text(session.title) },
                    supportingContent = { Text(listOfNotNull(session.subtitle.takeIf { it.isNotEmpty() }, status).joinToString("\n")) },
                    colors = ListItemDefaults.colors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        supportingColor = if (session.isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                )
            }
            if (list.count { !it.isCurrent } > 0) {
                item {
                    ListItem(
                        headlineContent = { Text("Завершить другие сеансы", color = MaterialTheme.colorScheme.error) },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                        modifier = Modifier.clickable { confirm = true },
                    )
                }
            }
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Завершить другие сеансы?") },
            text = { Text("На остальных устройствах нужно будет войти заново.") },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    scope.launch {
                        try {
                            repository.closeOthers()
                        } catch (e: kotlinx.coroutines.CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            error = (e as? OrbitleError)?.userMessage
                        }
                        load()
                    }
                }) { Text("Завершить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Отмена") } },
        )
    }
}
