package app.maxly.ui.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
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
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maxly.data.AppearanceSettings
import app.maxly.domain.AppFont
import app.maxly.domain.FontWeightScale
import app.maxly.domain.TextSizeStep
import app.maxly.ui.theme.LocalFontSource
import app.maxly.ui.theme.appFontFamily

/**
 * «Шрифт» из «Оформления»: образец переписки и списка чатов, выбор шрифта всего интерфейса
 * (название каждого — своим шрифтом), толщина ползунком и размер текста. Всё меняется сразу.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FontScreen(settings: AppearanceSettings, onBack: () -> Unit, outgoing: Color) {
    val prefs by settings.state.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Шрифт") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            FontPreview(outgoing)
            FontSection("Шрифт")
            val source = LocalFontSource.current
            AppFont.entries.forEach { font ->
                val family = remember(font, source) { source?.let { appFontFamily(font, FontWeightScale.DEFAULT, it) } ?: FontFamily.Default }
                FontRow(font.title, family, selected = prefs.font == font) { settings.setFont(font) }
            }
            FontSection("Толщина")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("A", fontSize = 18.sp, fontWeight = FontWeight.Light)
                Slider(
                    value = prefs.fontWeight.toFloat(),
                    onValueChange = { settings.setFontWeight(Math.round(it / 10f) * 10) },
                    valueRange = FontWeightScale.MIN.toFloat()..FontWeightScale.MAX.toFloat(),
                    modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
                )
                Text("A", fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                val note = if (prefs.font == AppFont.SYSTEM) " · у системного — ступенями" else ""
                Text(FontWeightScale.caption(prefs.fontWeight) + note, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                TextButton(onClick = { settings.setFontWeight(FontWeightScale.DEFAULT) }, enabled = prefs.fontWeight != FontWeightScale.DEFAULT) { Text("Сбросить") }
            }
            FontSection("Размер текста")
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
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun FontSection(title: String) {
    Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 20.dp, bottom = 8.dp))
}

/** Строка шрифта: название его же шрифтом, галочка у выбранного. */
@Composable
private fun FontRow(title: String, family: FontFamily, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, fontFamily = family, fontSize = 18.sp)
            Text("Съешь же ещё этих мягких булок", fontFamily = family, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (selected) Icon(Icons.Filled.Check, "Выбран", tint = MaterialTheme.colorScheme.primary)
    }
}

/** Образец: строка списка чатов и пара сообщений — выбранным шрифтом, толщиной и размером. */
@Composable
private fun FontPreview(outgoing: Color) {
    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(44.dp).clip(CircleShape).border(BorderStroke(0.dp, Color.Transparent), CircleShape)) {
                    Surface(color = MaterialTheme.colorScheme.primary, modifier = Modifier.fillMaxSize()) {
                        Box(contentAlignment = Alignment.Center) { Text("А", color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.SemiBold) }
                    }
                }
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Row {
                        Text("Анна", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Text("12:45", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("Встречаемся в шесть у фонтана?", color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Surface(shape = RoundedCornerShape(18.dp, 18.dp, 18.dp, 6.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Text("Доброе утро! Как тебе новый шрифт?", Modifier.padding(horizontal = 12.dp, vertical = 8.dp))
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                Surface(shape = RoundedCornerShape(18.dp, 18.dp, 6.dp, 18.dp), color = outgoing, contentColor = Color.White) {
                    Text("Читается отлично 👌", Modifier.padding(horizontal = 12.dp, vertical = 8.dp))
                }
            }
        }
    }
}
