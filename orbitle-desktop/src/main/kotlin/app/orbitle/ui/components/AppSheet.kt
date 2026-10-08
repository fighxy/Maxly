package app.orbitle.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.compose.ui.window.DialogModalityType
import androidx.compose.ui.window.WindowDecoration
import androidx.compose.ui.window.v2.DialogWindow
import androidx.compose.ui.window.v2.WindowBoundsProvider
import androidx.compose.ui.window.v2.WindowPositionProvider
import androidx.compose.ui.window.v2.WindowSizeProvider
import androidx.compose.ui.window.v2.rememberDialogState

/**
 * Модальное окно поверх родителя. Карточка Material 3 по центру, щелчок по затемнению закрывает.
 * Содержимое само решает, как прокручиваться. [wide] — списки пошире (пересылка, папки).
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun AppSheet(
    onDismissRequest: () -> Unit,
    wide: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val state = rememberDialogState(
        initialBoundsProvider = WindowBoundsProvider(
            positionProvider = WindowPositionProvider.AlignedToParentWindow(
                anchor = Alignment.TopStart,
                alignment = Alignment.TopStart,
            ),
            sizeProvider = WindowSizeProvider {
                val bounds = parentWindowMetrics?.bounds
                if (bounds == null) DpSize(640.dp, 720.dp) else DpSize(bounds.width, bounds.height)
            },
        ),
    )
    DialogWindow(
        onCloseRequest = onDismissRequest,
        state = state,
        title = "Orbitle",
        decoration = WindowDecoration.Undecorated(),
        transparent = true,
        resizable = false,
        modalityType = DialogModalityType.DocumentModal,
    ) {
        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.32f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onDismissRequest,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shadowElevation = 6.dp,
                tonalElevation = 3.dp,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = {},
                    )
                    .widthIn(min = 280.dp, max = if (wide) 720.dp else 560.dp)
                    .heightIn(max = maxHeight * 0.85f),
            ) {
                Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), content = content)
            }
        }
    }
}
