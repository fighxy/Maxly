package app.orbitle.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.MouseButton
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performMouseInput
import androidx.compose.ui.test.v2.runComposeUiTest
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Меню сообщения по правой кнопке: открывается слоем в том же окне, когда кнопку отпустили,
 * один раз даже на вложенных строках, и закрывается щелчком по затемнению.
 */
@OptIn(ExperimentalTestApi::class)
class AppSheetTest {
    @Test
    fun rightClickOpensSheetOnceOnRelease() = runComposeUiTest {
        var row = 0
        var inner = 0
        var open by mutableStateOf(false)
        setContent {
            Box(Modifier.fillMaxSize()) {
                Box(Modifier.size(300.dp).testTag("row").onSecondaryClick { row++; open = true }) {
                    // Фото внутри пузыря со своим обработчиком: меню не должно открыться дважды.
                    Box(Modifier.size(150.dp).onSecondaryClick { inner++ })
                }
                if (open) {
                    AppSheet(onDismissRequest = { open = false }) { Text("Ответить") }
                }
            }
        }
        onNodeWithTag("row").performMouseInput {
            moveTo(Offset(20f, 20f))
            press(MouseButton.Secondary)
        }
        waitForIdle()
        assertEquals(0, row)
        onNodeWithText("Ответить").assertDoesNotExist()

        onNodeWithTag("row").performMouseInput { release(MouseButton.Secondary) }
        waitForIdle()
        assertEquals(1, row)
        assertEquals(0, inner)
        onNodeWithText("Ответить").assertExists()
    }

    @Test
    fun leftClickDoesNotOpenMenu() = runComposeUiTest {
        var row = 0
        setContent { Box(Modifier.size(300.dp).testTag("row").onSecondaryClick { row++ }) }
        onNodeWithTag("row").performMouseInput { click() }
        waitForIdle()
        assertEquals(0, row)
    }

    @Test
    fun clickOnScrimClosesSheet() = runComposeUiTest {
        var open by mutableStateOf(true)
        setContent {
            Box(Modifier.size(800.dp).testTag("screen")) {
                if (open) AppSheet(onDismissRequest = { open = false }) { Text("Переслать") }
            }
        }
        onNodeWithText("Переслать").assertExists()
        onNodeWithTag("screen", useUnmergedTree = true).performMouseInput { click(Offset(5f, 5f)) }
        waitForIdle()
        assertEquals(false, open)
        onNodeWithText("Переслать").assertDoesNotExist()
    }
}
