package app.maxly.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.chat.VoicePlayback
import app.maxly.presentation.chat.VoicePlayer
import app.maxly.presentation.chat.VoiceSpeed
import app.maxly.ui.components.clickCursor

/** Плеер голосового и что делать по касанию имени (открыть чат на сообщении). */
class VoiceDockSource(val player: VoicePlayer, val onOpen: (VoicePlayback) -> Unit)

/** Играющее голосовое; `null` — ничего не играет. */
@Composable
fun rememberVoicePlayback(source: VoiceDockSource?): VoicePlayback? {
    val player = source?.player ?: return null
    val playback by player.playback.collectAsStateWithLifecycle()
    return playback
}

/**
 * Карточка у верха экрана: секции одна под другой через тонкий разделитель —
 * папки и плеер в списке чатов, плеер и закреп в чате. Пустые секции (`null`) пропускаются,
 * без секций карточки нет. Без соседа плеер висит один чуть ниже шапки.
 */
@Composable
fun TopDock(
    top: (@Composable ColumnScope.() -> Unit)?,
    bottom: (@Composable ColumnScope.() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    // Последние секции держатся, пока карточка уезжает.
    var shownTop by remember { mutableStateOf(top) }
    var shownBottom by remember { mutableStateOf(bottom) }
    val visible = top != null || bottom != null
    if (visible) {
        shownTop = top
        shownBottom = bottom
    }
    AnimatedVisibility(
        visible,
        modifier,
        enter = expandVertically() + fadeIn(),
        exit = shrinkVertically() + fadeOut(),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .clip(RoundedCornerShape(TopDockRadius))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .animateContentSize(),
        ) {
            val first = shownTop
            val second = shownBottom
            first?.invoke(this)
            if (first != null && second != null) {
                HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f))
            }
            second?.invoke(this)
        }
    }
}

private val TopDockRadius = 20.dp

/**
 * Строка плеера внутри [TopDock]: пуск и пауза, по центру автор и «Голосовое сообщение», скорость
 * 1X / 1.5X / 2X (голос не искажается), закрыть, внизу тонкая полоса прогресса. Касание по имени —
 * [VoiceDockSource.onOpen]: чат открывается на сообщении и оно подсвечивается.
 */
@Composable
fun VoicePlayerRow(playback: VoicePlayback, source: VoiceDockSource) {
    val player = source.player
    val accent = MaterialTheme.colorScheme.primary
    Box(Modifier.fillMaxWidth().height(48.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { if (playback.isPlaying) player.pause() else player.resume() }, modifier = Modifier.clickCursor()) {
                Icon(
                    if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    if (playback.isPlaying) "Пауза" else "Продолжить",
                    Modifier.size(26.dp),
                    tint = MaterialTheme.colorScheme.onSurface,
                )
            }
            Column(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .clickCursor()
                    .clickable { source.onOpen(playback) }
                    .padding(vertical = 4.dp, horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    playback.title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
                Text(
                    "Голосовое сообщение · ${clock(playback.positionMs)} / ${clock(playback.durationMs)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    textAlign = TextAlign.Center,
                )
            }
            val fast = playback.speed > 1f
            val speedColor = if (fast) accent else MaterialTheme.colorScheme.onSurfaceVariant
            Box(
                Modifier
                    .widthIn(min = 44.dp)
                    .height(40.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .clickCursor()
                    .clickable { player.setSpeed(VoiceSpeed.next(playback.speed)) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    VoiceSpeed.label(playback.speed).uppercase(),
                    color = speedColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .border(1.dp, speedColor.copy(alpha = 0.7f), RoundedCornerShape(5.dp))
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                )
            }
            IconButton(onClick = player::stop, modifier = Modifier.clickCursor()) {
                Icon(Icons.Filled.Close, "Закрыть", Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        // Прогресс — тонкая линия по низу строки.
        Canvas(Modifier.fillMaxWidth().height(2.dp).align(Alignment.BottomStart)) {
            val end = size.width * playback.progress.coerceIn(0f, 1f)
            if (end > 0f) {
                drawLine(accent, Offset(0f, size.height / 2), Offset(end, size.height / 2), strokeWidth = size.height, cap = StrokeCap.Round)
            }
        }
    }
}

private fun clock(ms: Long): String {
    val seconds = (ms.coerceAtLeast(0) / 1000).toInt()
    return "%d:%02d".format(seconds / 60, seconds % 60)
}
