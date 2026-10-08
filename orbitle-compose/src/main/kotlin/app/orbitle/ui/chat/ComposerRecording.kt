package app.orbitle.ui.chat

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.orbitle.presentation.chat.CallBubbleText
import app.orbitle.presentation.chat.RecordingController
import app.orbitle.presentation.chat.RecordingGesture
import app.orbitle.presentation.chat.RecordingMode
import app.orbitle.ui.components.clickCursor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Время и громкость идущей записи. */
data class RecordingLive(val elapsedMs: Long = 0, val level: Float = 0f)

/** Запись из поля ввода для экрана: состояние контроллера, время и жест кнопки. */
class RecordingUi(
    val state: RecordingController.State,
    val live: RecordingLive?,
    val gesture: Modifier,
    val controller: RecordingController?,
)

/**
 * Жест кнопки записи: палец вниз — [RecordingController.press], движение — сдвиг в dp,
 * отпускание — [RecordingController.release], обрыв жеста — [RecordingController.interrupt].
 */
@Composable
fun rememberRecordingUi(controller: RecordingController?, live: StateFlow<RecordingLive?>?): RecordingUi {
    val idle = remember { MutableStateFlow(RecordingController.State()) }
    val state by (controller?.state ?: idle).collectAsState()
    val empty = remember { MutableStateFlow<RecordingLive?>(null) }
    val current by (live ?: empty).collectAsState()
    val density = LocalDensity.current.density
    val gesture = Modifier.pointerInput(controller) {
        val rec = controller ?: return@pointerInput
        awaitEachGesture {
            val down = awaitFirstDown()
            down.consume()
            rec.press()
            val origin = down.position
            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == down.id }
                if (change == null) {
                    rec.interrupt()
                    break
                }
                if (!change.pressed) {
                    change.consume()
                    rec.release()
                    break
                }
                change.consume()
                rec.move((change.position.x - origin.x) / density, (change.position.y - origin.y) / density)
            }
        }
    }
    return RecordingUi(state, current, gesture, controller)
}

/** Кнопка справа от пустого поля: микрофон или камера; во время записи — крупный круг под пальцем. */
@Composable
fun RecordButton(ui: RecordingUi) {
    val state = ui.state
    val recording = state.phase == RecordingController.Phase.RECORDING
    val locked = state.phase == RecordingController.Phase.LOCKED || state.phase == RecordingController.Phase.FINISHING
    val video = (if (state.isActive) state.recording else state.mode) == RecordingMode.VIDEO
    val level by animateFloatAsState(ui.live?.level ?: 0f, label = "level")
    Box(contentAlignment = Alignment.Center) {
        if (recording) {
            // Подсказка закрепления над кнопкой, идёт за пальцем вверх.
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                modifier = Modifier
                    .offset(y = (-72).dp)
                    .graphicsLayer { translationY = maxOf(state.dragY, -RecordingGesture.LOCK_DISTANCE) * 0.4f * density }
                    .size(width = 32.dp, height = 48.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.Lock, "Вверх — закрепить", Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Box(
                Modifier
                    .size(84.dp)
                    .graphicsLayer {
                        scaleX = 1f + level * 0.6f
                        scaleY = scaleX
                    }
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.25f)),
            )
        }
        Box(
            Modifier
                .size(if (recording) 72.dp else 44.dp)
                .clip(CircleShape)
                .background(if (recording || locked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest)
                .clickCursor()
                .then(ui.gesture)
                .semantics {
                    contentDescription = when {
                        locked -> "Отправить запись"
                        video -> "Видеосообщение: удерживайте, чтобы записать, нажмите — голосовое"
                        else -> "Голосовое: удерживайте, чтобы записать, нажмите — видеосообщение"
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                when {
                    locked -> Icons.AutoMirrored.Filled.Send
                    video -> Icons.Filled.Videocam
                    else -> Icons.Filled.Mic
                },
                null,
                Modifier.size(if (recording) 30.dp else 24.dp),
                tint = if (recording || locked) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Полоса записи вместо поля ввода: точка, время, «Влево — отмена» или корзина у закреплённой. */
@Composable
fun RecordingBar(ui: RecordingUi, modifier: Modifier) {
    val state = ui.state
    val live = ui.live ?: RecordingLive()
    val level by animateFloatAsState(live.level, label = "level")
    val locked = state.phase == RecordingController.Phase.LOCKED
    Row(
        modifier
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(10.dp)
                .graphicsLayer { scaleX = 1f + level * 0.6f; scaleY = scaleX }
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.error),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            CallBubbleText.clock(live.elapsedMs),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.semantics { contentDescription = if (state.isVideo) "Идёт запись видеосообщения" else "Идёт запись" },
        )
        Spacer(Modifier.weight(1f))
        if (locked) {
            TextButton(onClick = { ui.controller?.cancel() }) {
                Icon(Icons.Outlined.Delete, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(4.dp))
                Text("Отмена", color = MaterialTheme.colorScheme.error)
            }
        } else if (state.phase == RecordingController.Phase.RECORDING) {
            val progress = RecordingGesture.cancelProgress(state.dragX)
            Text(
                "‹ Влево — отмена",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.graphicsLayer { translationX = state.dragX * density; alpha = 1f - progress * 0.8f },
            )
        }
    }
}
