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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import app.maxly.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.data.AppearanceSettings
import app.maxly.data.WallpaperPhotoSettings
import app.maxly.domain.ResolvedWallpaper
import app.maxly.domain.WallpaperScale
import app.maxly.ui.components.rememberWallpaperPicker
import app.maxly.domain.ChatWallpaper
import app.maxly.domain.TextSizeStep
import app.maxly.domain.ThemeMode
import app.maxly.ui.components.ChatBackdrop
import app.maxly.ui.components.ChatWallpaperBackground
import app.maxly.ui.components.LocalChatBackdrop
import app.maxly.ui.components.resource
import app.maxly.ui.theme.MaxlyOutgoing

/** «Оформление»: образец переписки, «Шрифт ›» (шрифт, толщина, размер), тема и обои чата. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceScreen(
    settings: AppearanceSettings,
    onBack: () -> Unit,
    /** Своё фото на обоях; `null` — блока «Выбрать фото…» нет. */
    photos: WallpaperPhotoSettings? = null,
) {
    val prefs by settings.state.collectAsStateWithLifecycle()
    val photoState = photos?.state?.collectAsStateWithLifecycle()?.value
    val globalPhoto = photoState?.globalPhoto
    val dark = LocalChatBackdrop.current.dark
    // «Шрифт ›» открывает свой экран поверх «Оформления»; «Назад» возвращает сюда.
    var fontOpen by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    if (fontOpen) {
        app.maxly.platform.BackHandler { fontOpen = false }
        app.maxly.ui.settings.FontScreen(settings, onBack = { fontOpen = false }, outgoing = MaxlyOutgoing)
        return
    }
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
            Preview(ChatBackdrop(prefs.wallpaper, dark, globalPhoto?.let { ResolvedWallpaper.Photo(it) } ?: ResolvedWallpaper.Preset))
            Section("Текст")
            androidx.compose.material3.ListItem(
                headlineContent = { Text("Шрифт") },
                supportingContent = { Text("Шрифт, толщина и размер текста") },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(prefs.fontSummary, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier.clip(RoundedCornerShape(12.dp)).clickable { fontOpen = true },
            )
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
                    WallpaperTile(choice, dark, selected = globalPhoto == null && prefs.wallpaper == choice) {
                        // Набор вместо своего фото: копия фото больше не нужна.
                        photos?.resetGlobal()
                        settings.setWallpaper(choice)
                    }
                }
            }
            if (photos != null) PhotoControls(photos, photoState ?: photos.state.value)
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** «Выбрать фото…», «Сбросить», затемнение 0–60 % и размытие для своего фото. */
@Composable
private fun PhotoControls(photos: WallpaperPhotoSettings, state: WallpaperPhotoSettings.State) {
    var failed by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    val pick = rememberWallpaperPicker(photos) { path ->
        failed = path == null
        if (path != null) photos.setGlobal(path)
    }
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = { failed = false; pick() }) { Text("Выбрать фото…") }
        TextButton(onClick = { failed = false; photos.resetGlobal() }, enabled = state.global != null) { Text("Сбросить") }
    }
    if (failed) {
        Text("Не удалось открыть фото — выберите JPEG, PNG или WebP", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
    }
    if (state.global != null) {
        Text("Затемнение — ${state.dimPercent}\u00A0%", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
        Slider(
            value = state.dimPercent.toFloat(),
            onValueChange = { photos.setDim(Math.round(it)) },
            valueRange = WallpaperScale.MIN_DIM.toFloat()..WallpaperScale.MAX_DIM.toFloat(),
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Размытие", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            androidx.compose.material3.Switch(checked = state.blur, onCheckedChange = photos::setBlur)
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
            Surface(shape = RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp), color = if (!backdrop.dark && backdrop.hasImage) Color.White else MaterialTheme.colorScheme.surfaceContainerHigh, contentColor = MaterialTheme.colorScheme.onSurface) {
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
