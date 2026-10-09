package app.maxly.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.domain.StorageCategory
import app.maxly.presentation.settings.StorageViewModel

/** «Данные и память»: сколько места занимает кэш и очистка отмеченных категорий. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StorageScreen(model: StorageViewModel, onBack: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    var confirm by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Данные и память") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        val usage = state.usage
        if (usage == null) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(StorageViewModel.format(usage.total), style = MaterialTheme.typography.displaySmall)
                Spacer(Modifier.height(4.dp))
                Text("занимает кэш Maxly", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            StorageCategory.entries.forEach { category ->
                val bytes = usage.of(category)
                ListItem(
                    leadingContent = {
                        Checkbox(category in state.selection, onCheckedChange = { model.toggle(category) }, enabled = !state.clearing)
                    },
                    headlineContent = { Text(category.title) },
                    supportingContent = {
                        Column {
                            Text(category.subtitle)
                            Spacer(Modifier.height(6.dp))
                            LinearProgressIndicator(progress = { state.share(category) }, modifier = Modifier.fillMaxWidth(), drawStopIndicator = {})
                        }
                    },
                    trailingContent = { Text(StorageViewModel.format(bytes)) },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    modifier = Modifier.clickable(enabled = !state.clearing) { model.toggle(category) },
                )
            }
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = { confirm = true },
                enabled = !state.clearing && state.selection.isNotEmpty() && state.selectedBytes > 0,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            ) {
                if (state.clearing) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text("Очистить ${StorageViewModel.format(state.selectedBytes)}")
                }
            }
            Text(
                "Сообщения останутся. Медиа снова скачаются из облака, когда понадобятся.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
            )
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Очистить кэш?") },
            text = { Text("Будет удалено ${StorageViewModel.format(state.selectedBytes)}. Сообщения останутся.") },
            confirmButton = {
                TextButton(onClick = {
                    confirm = false
                    model.clearSelected()
                }) { Text("Очистить", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Отмена") } },
        )
    }
}
