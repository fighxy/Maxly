package app.maxly.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.maxly.platform.BackHandler

/**
 * Лист поверх окна: карточка Material 3 по центру. Щелчок по затемнению и Esc закрывают.
 * Содержимое само решает, как прокручиваться. [wide] — списки пошире (пересылка, папки).
 *
 * Лист рисуется слоем в том же окне. Отдельное модальное окно ОС (`window.v2.DialogWindow`,
 * прозрачное и без рамки) на Windows вешало приложение: меню сообщения по правой кнопке
 * открывалось пустым окном, которое не отвечало, и закрыть программу удавалось только из
 * диспетчера задач.
 */
@Composable
fun AppSheet(
    onDismissRequest: () -> Unit,
    wide: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    // Esc перехватывает общий обработчик «назад» раньше слоя: лист кладёт в него себя сверху,
    // иначе Esc закрывал бы экран под листом, а лист оставался открытым.
    BackHandler(onBack = onDismissRequest)
    Dialog(
        onDismissRequest = onDismissRequest,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        // Карточка не выше 85 % окна: длинные списки прокручиваются внутри.
        val windowHeight = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.height.toDp() }
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shadowElevation = 6.dp,
            tonalElevation = 3.dp,
            modifier = Modifier
                .padding(24.dp)
                .widthIn(min = 280.dp, max = if (wide) 720.dp else 560.dp)
                .heightIn(max = (windowHeight * 0.85f).coerceAtLeast(240.dp)),
        ) {
            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), content = content)
        }
    }
}
