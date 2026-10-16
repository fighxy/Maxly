package app.maxly.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.domain.OutgoingFile
import app.maxly.presentation.gifs.GifSearchModel
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch

/**
 * Вкладка «GIF»: поиск по gifka.me, без запроса — популярное. Выбранная гифка скачивается
 * как `.gif` и уходит через [onGif] обычным вложением.
 */
@Composable
fun GifSearchPanel(model: GifSearchModel, onGif: (OutgoingFile) -> Unit, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    LaunchedEffect(model) { model.open() }
    Column(modifier.fillMaxSize()) {
        OutlinedTextField(
            value = state.query,
            onValueChange = model::onQuery,
            placeholder = { Text("Поиск гифок") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (state.query.isBlank()) "Популярное" else "Результаты",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            Text(GifSearchModel.ATTRIBUTION, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (!state.canSend) {
            Text(
                GifSearchModel.NO_KEY,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
            )
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyVerticalGrid(
                GridCells.Adaptive(110.dp),
                contentPadding = PaddingValues(8.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(state.items, key = { it.id }) { media ->
                    val ratio = if (media.width > 0 && media.height > 0) (media.width.toFloat() / media.height).coerceIn(.5f, 2f) else 1f
                    Box(
                        Modifier.padding(2.dp).aspectRatio(ratio).clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                            .clickable(enabled = state.canSend && state.sendingId == null) {
                                scope.launch { model.prepare(media)?.let(onGif) }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        AsyncImage(media.webpUrl ?: media.posterUrl, media.title.ifEmpty { "Гифка" }, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        if (state.sendingId == media.id) {
                            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .4f)), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(28.dp), color = Color.White)
                            }
                        }
                    }
                }
            }
            when {
                state.loading && state.items.isEmpty() -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                state.error != null -> Column(
                    Modifier.align(if (state.items.isEmpty()) Alignment.Center else Alignment.BottomCenter)
                        .padding(8.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(state.error.orEmpty(), style = MaterialTheme.typography.bodyMedium)
                    if (state.error != GifSearchModel.EMPTY && state.error != GifSearchModel.NO_KEY) {
                        TextButton(onClick = model::retry) { Text("Повторить") }
                    }
                }
            }
        }
    }
}

/** Модель вкладки «GIF», пока поиск включён в настройках; иначе `null`. */
@Composable
fun rememberGifSearch(
    settings: app.maxly.data.GifSettings,
    client: app.maxly.data.gifka.GifkaClient,
    outgoingDir: java.io.File,
): GifSearchModel? {
    val prefs by settings.state.collectAsStateWithLifecycle()
    if (!app.maxly.data.GifSettings.searchAvailable(prefs)) return null
    val scope = rememberCoroutineScope()
    return androidx.compose.runtime.remember(client) {
        GifSearchModel(client, scope, { outgoingDir }, canSend = client.hasKey)
    }
}
