package app.orbitle.ui.components

import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput

/** Под мышью нажимаемое показывает руку, как ссылки и кнопки в браузере. */
fun Modifier.clickCursor(): Modifier = pointerHoverIcon(PointerIcon.Hand)

/**
 * Правый клик мыши — то же, что долгое нажатие пальцем: меню строки. Касание и левая кнопка
 * идут дальше как обычно.
 *
 * Меню открывается, когда кнопку отпустили, как в Windows: к этому времени нажатие закончено,
 * и отпускание не достаётся только что открытому меню. Нажатие и отпускание поглощаются
 * на первом проходе, поэтому вложенные строки с тем же обработчиком не открывают меню второй раз.
 */
fun Modifier.onSecondaryClick(action: () -> Unit): Modifier = composed {
    // Обработчик не перезапускается от новой лямбды на каждой перерисовке: иначе нажатие,
    // начатое до перерисовки (её вызывает и наведение), терялось бы вместе с отпусканием.
    val current by rememberUpdatedState(action)
    pointerInput(Unit) {
        awaitPointerEventScope {
            var pressed = false
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                when (event.type) {
                    PointerEventType.Press -> {
                        pressed = event.buttons.isSecondaryPressed && event.changes.none { it.isConsumed }
                        if (pressed) event.changes.forEach { it.consume() }
                    }
                    PointerEventType.Release -> if (pressed && !event.buttons.isSecondaryPressed) {
                        pressed = false
                        event.changes.forEach { it.consume() }
                        current()
                    }
                    PointerEventType.Exit -> pressed = false
                }
            }
        }
    }
}
