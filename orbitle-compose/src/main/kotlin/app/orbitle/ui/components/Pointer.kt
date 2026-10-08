package app.orbitle.ui.components

import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput

/** Под мышью нажимаемое показывает руку, как ссылки и кнопки в Telegram Desktop. */
fun Modifier.clickCursor(): Modifier = pointerHoverIcon(PointerIcon.Hand)

/**
 * Правый клик мыши — то же, что долгое нажатие пальцем: меню строки. Касание и левая кнопка
 * идут дальше как обычно.
 */
fun Modifier.onSecondaryClick(action: () -> Unit): Modifier = pointerInput(action) {
    awaitPointerEventScope {
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            if (event.type == PointerEventType.Press && event.buttons.isSecondaryPressed) {
                event.changes.forEach { it.consume() }
                action()
            }
        }
    }
}
