package app.maxly.ui.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.data.AppearanceSettings
import app.maxly.domain.ChatWallpaper
import app.maxly.domain.TextSizeStep
import app.maxly.domain.ThemeMode
import app.maxly.ui.components.ChatBackdrop
import app.maxly.ui.components.ChatWallpaperBackground
import app.maxly.ui.components.LocalChatBackdrop
import app.maxly.ui.components.resource
import app.maxly.ui.theme.MaxlyOutgoing

/** «Оформление»: образец переписки, размер текста, тема и обои чата. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceScreen(settings: AppearanceSettings, onBack: () -> Unit) {
    val prefs by settings.state.collectAsStateWithLifecycle()
    val dark = LocalChatBackdrop.current.dark
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Оформление") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Preview(ChatBackdrop(prefs.wallpaper, dark))
            Section("Размер текста")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("A", fontSize = 13.sp)
                Slider(
                    value = prefs.textSize.ordinal.toFloat(),
                    onValueChange = { settings.setTextSize(TextSizeStep.of(Math.round(it))) },
                    valueRange = 0f..TextSizeStep.maxIndex.toFloat(),
                    steps = TextSizeStep.maxIndex - 1,
                    modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
                )
                Text("A", fontSize = 22.sp)
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(prefs.textSize.caption, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                TextButton(onClick = { settings.setTextSize(TextSizeStep.STANDARD) }, enabled = prefs.textSize != TextSizeStep.STANDARD) { Text("Сбросить") }
            }
            Section("Тема")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ThemeMode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = prefs.theme == mode,
                        onClick = { settings.setTheme(mode) },
                        shape = SegmentedButtonDefaults.itemShape(index, ThemeMode.entries.size),
                    ) { Text(mode.title) }
                }
            }
            Section("Обои чата")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ChatWallpaper.entries.forEach { choice ->
                    WallpaperTile(choice, dark, selected = prefs.wallpaper == choice) { settings.setWallpaper(choice) }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun Section(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 20.dp, bottom = 8.dp),
    )
}

/** Образец: чужое и своё сообщение на выбранных обоях с выбранным размером текста. */
@Composable
private fun Preview(backdrop: ChatBackdrop) {
    Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(20.dp))) {
        ChatWallpaperBackground(backdrop)
        Column(Modifier.fillMaxSize().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
            Surface(shape = RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Text("Доброе утро! Как тебе новые обои?", Modifier.padding(horizontal = 12.dp, vertical = 8.dp), fontSize = 16.sp)
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                Surface(shape = RoundedCornerShape(18.dp, 18.dp, 6.dp, 18.dp), color = MaxlyOutgoing, contentColor = Color.White) {
                    Text("Очень уютно 🍂", Modifier.padding(horizontal = 12.dp, vertical = 8.dp), fontSize = 16.sp)
                }
            }
        }
    }
}

@Composable
private fun WallpaperTile(choice: ChatWallpaper, dark: Boolean, selected: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(84.dp)) {
        val shape = RoundedCornerShape(14.dp)
        Box(
            Modifier
                .size(84.dp, 120.dp)
                .clip(shape)
                .border(if (selected) BorderStroke(3.dp, MaterialTheme.colorScheme.primary) else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), shape)
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            val image = choice.image(dark)
            if (image == null) {
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLowest))
            } else {
                Image(painterResource(image.resource(thumb = true)), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
            if (selected) {
                Box(Modifier.size(28.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(18.dp))
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(choice.title, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center, maxLines = 2)
    }
}
