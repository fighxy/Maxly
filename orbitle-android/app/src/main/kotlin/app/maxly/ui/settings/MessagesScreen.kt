package app.maxly.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.chat.ReactionPalette
import app.maxly.presentation.settings.AccountSettingsViewModel

/** «Сообщения»: быстрая реакция, которую ставит двойное нажатие в чате. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesScreen(
    model: AccountSettingsViewModel,
    loadCatalog: suspend () -> List<String>,
    onBack: () -> Unit,
) {
    val settings = model.state.collectAsStateWithLifecycle().value.settings
    var picking by remember { mutableStateOf(false) }
    var catalog by remember { mutableStateOf(ReactionPalette.FALLBACK) }
    LaunchedEffect(picking) {
        if (!picking) return@LaunchedEffect
        val loaded = runCatching { loadCatalog() }.getOrDefault(emptyList()).filter { it.isNotBlank() }
        if (loaded.isNotEmpty()) catalog = loaded
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Сообщения") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().padding(horizontal = 20.dp)) {
            Text("Быстрые реакции", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
            Text(
                "Дважды нажмите на сообщение, чтобы поставить выбранную реакцию.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth().padding(bottom = 28.dp), contentAlignment = Alignment.Center) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier
                        .size(76.dp)
                        .clip(CircleShape)
                        .clickable { picking = true }
                        .semantics { contentDescription = "Выбрать быструю реакцию" },
                ) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(settings.quickReaction, fontSize = 36.sp, textAlign = TextAlign.Center)
                    }
                }
            }
        }
    }
    if (picking) {
        ModalBottomSheet(onDismissRequest = { picking = false }) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
            ) {
                Text("Выберите реакцию", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
                catalog.chunked(6).forEach { row ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                        row.forEach { emoji ->
                            TextButton(onClick = {
                                model.setQuickReaction(emoji)
                                picking = false
                            }) {
                                Text(emoji, fontSize = 28.sp)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}
