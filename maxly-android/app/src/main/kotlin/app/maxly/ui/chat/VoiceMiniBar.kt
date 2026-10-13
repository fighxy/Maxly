package app.maxly.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.chat.VoicePlayback
import app.maxly.presentation.chat.VoicePlayer
import app.maxly.presentation.chat.VoiceSpeed

/**
 * Полоса «играет голосовое» над чатом и списком чатов, как в популярных мессенджерах: пуск и
 * пауза, автор и время, скорость 1x / 1.5x / 2x (голос не искажается), закрыть. Касание по
 * имени — [onOpen]: чат открывается на сообщении и оно подсвечивается.
 */
@Composable
fun VoiceMiniBar(player: VoicePlayer, onOpen: (VoicePlayback) -> Unit, modifier: Modifier = Modifier) {
    val playback by player.playback.collectAsStateWithLifecycle()
    // Последнее значение держится, пока полоса уезжает.
    var shown by remember { mutableStateOf<VoicePlayback?>(null) }
    playback?.let { shown = it }
    AnimatedVisibility(playback != null, modifier, enter = expandVertically(), exit = shrinkVertically()) {
        val current = shown ?: return@AnimatedVisibility
        Surface(color = MaterialTheme.colorScheme.surfaceContainerHigh) {
            Column {
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { if (current.isPlaying) player.pause() else player.resume() }) {
                        Icon(
                            if (current.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            if (current.isPlaying) "Пауза" else "Продолжить",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Column(
                        Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { onOpen(current) }.padding(vertical = 6.dp, horizontal = 4.dp),
                    ) {
                        Text(current.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            "Голосовое сообщение · ${clock(current.positionMs)} / ${clock(current.durationMs)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                        )
                    }
                    Surface(
                        onClick = { player.setSpeed(VoiceSpeed.next(current.speed)) },
                        shape = RoundedCornerShape(8.dp),
                        color = if (current.speed > 1f) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest,
                        contentColor = if (current.speed > 1f) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                    ) {
                        Text(VoiceSpeed.label(current.speed), style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
                    }
                    IconButton(onClick = player::stop) {
                        Icon(Icons.Filled.Close, "Закрыть", Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                LinearProgressIndicator(
                    progress = { current.progress },
                    modifier = Modifier.fillMaxWidth().height(2.dp),
                    drawStopIndicator = {},
                    gapSize = 0.dp,
                )
            }
        }
    }
}

private fun clock(ms: Long): String {
    val seconds = (ms.coerceAtLeast(0) / 1000).toInt()
    return "%d:%02d".format(seconds / 60, seconds % 60)
}
