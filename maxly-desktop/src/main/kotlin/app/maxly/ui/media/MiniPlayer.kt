package app.maxly.ui.media

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.rememberWindowState
import app.maxly.presentation.media.MediaTimeText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first

/**
 * Картинка в картинке на компьютере: ролик из просмотра играет в маленьком окне поверх всех
 * окон, с того же места. Окно двигается и меняет размер как обычное; крестик закрывает его.
 */
object MiniPlayer {
    /** Ролик: адрес (скачанный уже лежит в кэше), с какой миллисекунды и чей. */
    data class Clip(val url: String, val userAgent: String, val startMs: Long, val title: String)

    private val _clip = MutableStateFlow<Clip?>(null)
    val clip: StateFlow<Clip?> = _clip.asStateFlow()

    fun show(clip: Clip) { _clip.value = clip }

    fun close() { _clip.value = null }
}

/** Окно мини-плеера, пока есть ролик. Живёт рядом с главным окном в `application`. */
@Composable
fun MiniPlayerWindow() {
    val clip by MiniPlayer.clip.collectAsState()
    val current = clip ?: return
    val state = rememberWindowState(size = DpSize(420.dp, 260.dp), position = WindowPosition(Alignment.BottomEnd))
    Window(
        onCloseRequest = MiniPlayer::close,
        title = current.title.ifEmpty { "Видео" },
        state = state,
        alwaysOnTop = true,
    ) {
        // Новый ролик — новый проигрыватель.
        key(current) { MiniPlayerContent(current) }
    }
}

@Composable
private fun MiniPlayerContent(clip: MiniPlayer.Clip) {
    val player = rememberVideoPlayer()
    val state by player.state.collectAsState()
    LaunchedEffect(clip) {
        player.open(clip.url, clip.userAgent, autoplay = true)
        if (clip.startMs <= 0) return@LaunchedEffect
        // Перемотка — когда известна длина ролика.
        val ready = player.state.first { it.durationMs > 0 || it.failed }
        if (!ready.failed) player.seekTo(clip.startMs)
    }
    val hover = androidx.compose.runtime.remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .hoverable(hover)
            .pointerInput(player) { detectTapGestures(onTap = { player.toggle() }) },
        contentAlignment = Alignment.Center,
    ) {
        VideoFrame(state, Modifier.fillMaxSize())
        when {
            state.failed -> Text("Видео не воспроизводится", color = Color.White.copy(alpha = 0.8f), fontSize = 13.sp)
            state.isBuffering && (state.frame == null || state.isPlaying) -> CircularProgressIndicator(color = Color.White)
        }
        AnimatedVisibility(hovered || !state.isPlaying, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomCenter)) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = player::toggle) {
                    val icon = when {
                        state.ended -> Icons.Filled.Replay
                        state.isPlaying -> Icons.Filled.Pause
                        else -> Icons.Filled.PlayArrow
                    }
                    Icon(icon, if (state.isPlaying) "Пауза" else "Смотреть", tint = Color.White, modifier = Modifier.size(22.dp))
                }
                Text(
                    "${MediaTimeText.clock(state.positionMs)} / ${if (state.durationMs > 0) MediaTimeText.clock(state.durationMs) else "–:––"}",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = 12.sp,
                )
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
