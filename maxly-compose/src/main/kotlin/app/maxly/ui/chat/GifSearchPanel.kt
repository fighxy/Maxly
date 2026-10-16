package app.maxly.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.data.gifka.GifkaReportReason
import app.maxly.domain.GifkaMedia
import app.maxly.domain.PreparedPhoto
import app.maxly.presentation.gifs.GifSearchModel
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay

/**
 * Вкладка «GIF»: поиск по gifka.me, без запроса — популярное. Выбор отдаёт [onGif] сообщение,
 * которое сразу встаёт в ленту; GIF качается уже там. Долгое нажатие — «Пожаловаться».
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun GifSearchPanel(
    model: GifSearchModel,
    onGif: (PreparedPhoto) -> Unit,
    modifier: Modifier = Modifier,
    /** Поле поиска в фокусе: на телефоне клавиатура тогда не закрывает панель. */
    onSearchFocus: (Boolean) -> Unit = {},
) {
    val state by model.state.collectAsStateWithLifecycle()
    val uri = LocalUriHandler.current
    var menuFor by remember { mutableStateOf<GifkaMedia?>(null) }
    var reporting by remember { mutableStateOf<GifkaMedia?>(null) }
    LaunchedEffect(model) { model.open() }
    LaunchedEffect(state.notice) {
        if (state.notice != null) {
            delay(2500)
            model.noticeShown()
        }
    }
    Column(modifier.fillMaxSize()) {
        OutlinedTextField(
            value = state.query,
            onValueChange = model::onQuery,
            placeholder = { Text("Поиск гифок") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)
                .onFocusChanged { onSearchFocus(it.isFocused) },
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                state.notice ?: if (state.query.isBlank()) "Популярное" else "Результаты",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            Text(
                GifSearchModel.ATTRIBUTION,
                style = MaterialTheme.typography.labelSmall.copy(textDecoration = TextDecoration.Underline),
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .clickable(role = Role.Button) { runCatching { uri.openUri(GifSearchModel.ATTRIBUTION_URL) } }
                    .semantics { contentDescription = "Открыть сайт gifka.me" }
                    .padding(vertical = 4.dp),
            )
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
                            .combinedClickable(
                                onLongClick = if (GifSearchModel.REPORTS_ENABLED) ({ menuFor = media }) else null,
                                onClick = { model.pick(media)?.let(onGif) },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        AsyncImage(media.webpUrl ?: media.posterUrl, media.title.ifEmpty { "Гифка" }, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        DropdownMenu(expanded = menuFor?.id == media.id, onDismissRequest = { menuFor = null }) {
                            DropdownMenuItem(
                                text = { Text("Пожаловаться") },
                                onClick = {
                                    reporting = media
                                    menuFor = null
                                },
                            )
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
    reporting?.let { media ->
        AlertDialog(
            onDismissRequest = { reporting = null },
            title = { Text("Пожаловаться на гифку") },
            text = {
                Column {
                    GifkaReportReason.entries.forEach { reason ->
                        Text(
                            reason.title,
                            modifier = Modifier.fillMaxWidth().clickable {
                                model.report(media, reason)
                                reporting = null
                            }.padding(vertical = 10.dp),
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { reporting = null }) { Text("Отмена") } },
        )
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
    return remember(client) {
        GifSearchModel(client, scope, { outgoingDir }, canSend = client.hasKey)
    }
}
