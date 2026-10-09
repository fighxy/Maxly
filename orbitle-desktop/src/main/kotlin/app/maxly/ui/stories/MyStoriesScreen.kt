package app.maxly.ui.stories

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.domain.Story
import app.maxly.presentation.stories.MyStoriesViewModel
import coil3.compose.AsyncImage
import java.time.Instant
import java.time.ZoneId

/**
 * «Мои истории»: свой архив (219) сеткой, страницы по 30 подгружаются у конца списка.
 * Пустой архив предлагает «Создать историю» — тот же выбор файла, что и в полосе историй.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyStoriesScreen(model: MyStoriesViewModel, onCreate: () -> Unit, onBack: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Мои истории") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                !state.loaded && state.error != null -> Column(
                    Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(state.error.orEmpty(), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    TextButton(onClick = model::reload) { Text("Повторить") }
                }
                !state.loaded -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                state.isEmpty -> Column(
                    Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Здесь будут ваши истории", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Опубликованные истории появятся в этом списке.",
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onCreate) { Text("Создать историю") }
                }
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(110.dp),
                    contentPadding = PaddingValues(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    itemsIndexed(state.stories, key = { _, story -> story.id }) { index, story ->
                        if (index >= state.stories.size - 6) LaunchedEffect(state.stories.size) { model.loadMore() }
                        ArchiveTile(story)
                    }
                    if (state.loading || state.error != null) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                                if (state.loading) CircularProgressIndicator()
                                else TextButton(onClick = model::loadMore) { Text("Повторить") }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ArchiveTile(story: Story) {
    val media = story.media
    val cover = media?.let { if (it.isVideo) it.thumbnailUrl else it.url }
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(9f / 16f)
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        if (cover != null) AsyncImage(cover, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        Text(
            archiveDate(story.timeMs),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(6.dp)
                .background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(6.dp))
                .padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

private fun archiveDate(timeMs: Long): String {
    if (timeMs <= 0L) return ""
    val date = Instant.ofEpochMilli(timeMs).atZone(ZoneId.systemDefault())
    return "%02d.%02d.%04d".format(date.dayOfMonth, date.monthValue, date.year)
}
