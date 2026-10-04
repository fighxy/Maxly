package app.orbitle.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.domain.AnimatedEmoji
import app.orbitle.domain.Sticker
import app.orbitle.presentation.stickers.StickerPanel
import app.orbitle.presentation.stickers.StickerPanelState
import app.orbitle.presentation.stickers.emojiTabs
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch

/** Панель эмодзи и стикеров вместо клавиатуры. */
@Composable
fun StickerPanelView(
    panel: StickerPanel,
    height: Dp,
    onEmoji: (String) -> Unit,
    onSticker: (Sticker) -> Unit,
    onAnimoji: (AnimatedEmoji) -> Unit = {},
) {
    val state by panel.state.collectAsStateWithLifecycle()
    LaunchedEffect(panel) { panel.prepare() }
    Column(Modifier.fillMaxWidth().height(height).background(MaterialTheme.colorScheme.surfaceContainer)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
            StickerPanelState.Mode.entries.forEachIndexed { index, mode ->
                SegmentedButton(
                    selected = state.mode == mode,
                    onClick = { panel.setMode(mode) },
                    shape = SegmentedButtonDefaults.itemShape(index, StickerPanelState.Mode.entries.size),
                    icon = {},
                ) { Text(if (mode == StickerPanelState.Mode.EMOJI) "Эмодзи" else "Стикеры") }
            }
        }
        when (state.mode) {
            StickerPanelState.Mode.EMOJI -> EmojiGrid(
                state,
                onEmoji = {
                    panel.usedEmoji(it)
                    onEmoji(it)
                },
                onAnimoji = {
                    panel.usedAnimated(it)
                    onAnimoji(it)
                },
            )
            StickerPanelState.Mode.STICKERS -> StickerGrid(panel, state, onSticker)
        }
    }
}

@Composable
private fun EmojiGrid(state: StickerPanelState, onEmoji: (String) -> Unit, onAnimoji: (AnimatedEmoji) -> Unit) {
    val grid = rememberLazyGridState()
    val scope = rememberCoroutineScope()
    val tabs = remember(state.emoji, state.animated) { emojiTabs(state) }
    // Начало каждого раздела в сетке: заголовок плюс его ячейки.
    val starts = remember(tabs) {
        var index = 0
        tabs.map { tab -> index.also { index += 1 + tab.picks.size } }
    }
    val current by remember(starts) { derivedStateOf { starts.indexOfLast { it <= grid.firstVisibleItemIndex }.coerceAtLeast(0) } }
    Column {
        LazyRow(Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 8.dp)) {
            itemsIndexed(tabs, key = { _, tab -> tab.id }) { index, tab ->
                Box(
                    Modifier.size(40.dp).clip(CircleShape)
                        .background(if (index == current) MaterialTheme.colorScheme.primary.copy(alpha = 0.16f) else MaterialTheme.colorScheme.surfaceContainer)
                        .clickable { scope.launch { grid.scrollToItem(starts[index]) } },
                    contentAlignment = Alignment.Center,
                ) {
                    when (tab.id) {
                        "recent" -> Icon(Icons.Outlined.Schedule, tab.title, Modifier.size(20.dp))
                        "animated" -> Icon(Icons.Outlined.AutoAwesome, tab.title, Modifier.size(20.dp))
                        else -> Text(tab.picks.first().glyph, fontSize = 20.sp)
                    }
                }
            }
        }
        LazyVerticalGrid(GridCells.Adaptive(44.dp), state = grid, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 6.dp, vertical = 4.dp)) {
            tabs.forEach { tab ->
                item(key = "h-${tab.id}", span = { GridItemSpan(maxLineSpan) }) {
                    Text(tab.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 6.dp, top = 8.dp, bottom = 4.dp))
                }
                items(tab.picks, key = { it.key }) { pick ->
                    Box(
                        Modifier.aspectRatio(1f).clip(RoundedCornerShape(10.dp)).clickable {
                            val animated = pick.animated
                            if (animated != null) onAnimoji(animated) else onEmoji(pick.glyph)
                        },
                        contentAlignment = Alignment.Center,
                    ) {
                        // В сетке картинка: десятки Lottie сразу тормозили бы панель. Анимация — в сообщении.
                        val icon = pick.animated?.iconUrl
                        if (!icon.isNullOrBlank()) AsyncImage(icon, pick.glyph, Modifier.size(34.dp), contentScale = ContentScale.Fit)
                        else Text(pick.glyph, fontSize = 26.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun StickerGrid(panel: StickerPanel, state: StickerPanelState, onSticker: (Sticker) -> Unit) {
    val grid: LazyGridState = rememberLazyGridState()
    val scope = rememberCoroutineScope()
    val starts = remember(state.sections) {
        var index = 0
        state.sections.map { section -> index.also { index += 1 + section.stickerIds.size } }
    }
    val current by remember(starts) { derivedStateOf { starts.indexOfLast { it <= grid.firstVisibleItemIndex }.coerceAtLeast(0) } }
    // Видимый раздел и следующий за ним: их стикеры догружаются.
    LaunchedEffect(state.sections) {
        snapshotFlow { current }.collect { index ->
            state.sections.getOrNull(index)?.let(panel::load)
            state.sections.getOrNull(index + 1)?.let(panel::load)
        }
    }
    when {
        state.sections.isEmpty() && state.isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        state.sections.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(state.failure ?: "Стикеров пока нет", color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (state.failure != null) TextButton(onClick = panel::prepare) { Text("Повторить") }
            }
        }
        else -> Column {
            LazyRow(Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                itemsIndexed(state.sections, key = { _, s -> s.id }) { index, section ->
                    Box(
                        Modifier.size(40.dp).clip(RoundedCornerShape(10.dp))
                            .background(if (index == current) MaterialTheme.colorScheme.primary.copy(alpha = 0.16f) else MaterialTheme.colorScheme.surfaceContainer)
                            .clickable { scope.launch { grid.scrollToItem(starts[index]) } },
                        contentAlignment = Alignment.Center,
                    ) {
                        val icon = section.iconUrl ?: section.stickerIds.firstOrNull()?.let { state.stickers[it]?.url }
                        if (section.id == "recent") Icon(Icons.Outlined.Schedule, section.title, Modifier.size(20.dp))
                        else AsyncImage(icon, section.title, Modifier.size(32.dp), contentScale = ContentScale.Fit)
                    }
                }
            }
            LazyVerticalGrid(GridCells.Adaptive(76.dp), state = grid, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(6.dp)) {
                state.sections.forEach { section ->
                    item(key = "h-${section.id}", span = { GridItemSpan(maxLineSpan) }) {
                        Text(section.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 6.dp, top = 8.dp, bottom = 4.dp))
                    }
                    items(section.stickerIds, key = { "${section.id}:$it" }) { id ->
                        val sticker = state.stickers[id]
                        Box(
                            Modifier.aspectRatio(1f).padding(3.dp).clip(RoundedCornerShape(10.dp))
                                .clickable(enabled = sticker != null) { sticker?.let(onSticker) },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (sticker != null) AsyncImage(sticker.url, "Стикер", Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                            else Box(Modifier.size(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh))
                        }
                    }
                }
            }
        }
    }
}
