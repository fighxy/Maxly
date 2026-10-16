package app.maxly.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.data.GifSettings
import app.maxly.domain.GifAutoplay

/**
 * «Гифки» в настройках сообщений: автовоспроизведение и поиск gifka.me.
 * [modes] — какие варианты показать (на компьютере нет «Только по Wi‑Fi»).
 */
@Composable
fun GifSettingsSection(
    settings: GifSettings,
    modes: List<GifAutoplay> = GifAutoplay.entries,
    modifier: Modifier = Modifier,
) {
    val prefs by settings.state.collectAsStateWithLifecycle()
    Column(modifier.fillMaxWidth()) {
        Text("Гифки", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
        Text(
            "Автовоспроизведение",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
        )
        modes.forEach { mode ->
            val selected = prefs.autoplay == mode || (mode == GifAutoplay.ALWAYS && prefs.autoplay !in modes)
            Row(
                Modifier.fillMaxWidth()
                    .selectable(selected, role = Role.RadioButton) { settings.setAutoplay(mode) }
                    .padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected, onClick = null)
                Text(title(mode), modifier = Modifier.padding(start = 12.dp))
            }
        }
        Row(
            Modifier.fillMaxWidth().clickable { settings.setGifkaSearch(!prefs.gifkaSearch) }.padding(top = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Поиск гифок через gifka.me", modifier = Modifier.weight(1f))
            Switch(prefs.gifkaSearch, onCheckedChange = settings::setGifkaSearch)
        }
        Text(
            "Добавляет вкладку «GIF» в панель стикеров. Поисковые запросы и ваш IP-адрес " +
                "отправляются сервису gifka.me. По умолчанию выключено.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

private fun title(mode: GifAutoplay) = when (mode) {
    GifAutoplay.ALWAYS -> "Всегда"
    GifAutoplay.WIFI_ONLY -> "Только по Wi‑Fi"
    GifAutoplay.NEVER -> "Никогда"
}
