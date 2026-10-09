package app.maxly.ui.media

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maxly.media.DesktopVideoPlayer
import app.maxly.presentation.chat.CallBubbleText

/** Проигрыватель, который живёт, пока экран на месте, и отпускает ffmpeg и звук при уходе. */
@Composable
fun rememberVideoPlayer(): DesktopVideoPlayer {
    val scope = rememberCoroutineScope()
    val player = remember { DesktopVideoPlayer(scope) }
    DisposableEffect(player) { onDispose { player.release() } }
    return player
}

/** Текущий кадр ролика; до первого кадра пусто. */
@Composable
fun VideoFrame(state: DesktopVideoPlayer.State, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Fit) {
    Box(modifier, contentAlignment = Alignment.Center) {
        state.frame?.let { Image(it, contentDescription = "Видео", contentScale = contentScale, modifier = Modifier.matchParentSize()) }
    }
}

/** Пуск и пауза, полоса перемотки и время — внизу экрана просмотра. */
@Composable
fun VideoControls(player: DesktopVideoPlayer, state: DesktopVideoPlayer.State, modifier: Modifier = Modifier) {
    // Пока ползунок тянут, позиция — его, а не ролика: перемотка уходит, когда его отпустили.
    var dragging by remember { mutableStateOf<Float?>(null) }
    Row(
        modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = player::toggle) {
            val icon = when {
                state.ended -> Icons.Filled.Replay
                state.isPlaying -> Icons.Filled.Pause
                else -> Icons.Filled.PlayArrow
            }
            Icon(icon, if (state.isPlaying) "Пауза" else "Смотреть", tint = Color.White)
        }
        Text(CallBubbleText.clock(state.positionMs), color = Color.White, fontSize = 12.sp)
        Spacer(Modifier.width(8.dp))
        Slider(
            value = dragging ?: state.progress,
            onValueChange = { dragging = it },
            onValueChangeFinished = {
                dragging?.let(player::seek)
                dragging = null
            },
            enabled = state.durationMs > 0,
            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.3f)),
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(8.dp))
        Text(if (state.durationMs > 0) CallBubbleText.clock(state.durationMs) else "–:––", color = Color.White, fontSize = 12.sp)
    }
}
