package app.maxly.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.v2.runComposeUiTest
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.maxly.domain.AppFont
import org.junit.Assert.assertTrue
import org.junit.Test

/** Встроенные шрифты грузятся из ресурсов, а ползунок толщины меняет начертание (шире строка). */
@OptIn(ExperimentalTestApi::class)
class AppFontsTest {
    private fun width(font: AppFont, weight: Int, bold: Boolean = false): Float {
        var measured = 0f
        runComposeUiTest {
            setContent {
                MaxlyTheme(darkTheme = false, font = font, fontWeight = weight) {
                    Text(
                        "Съешь же ещё этих мягких французских булок",
                        fontSize = 20.sp,
                        fontWeight = if (bold) FontWeight.SemiBold else null,
                        style = MaterialTheme.typography.bodyLarge,
                        onTextLayout = { measured = it.size.width.toFloat() },
                    )
                }
            }
            waitForIdle()
        }
        return measured
    }

    @Test
    fun weightSliderWidensBundledFonts() {
        AppFont.entries.filter { it.file != null }.forEach { font ->
            val light = width(font, 300)
            val regular = width(font, 400)
            val heavy = width(font, 600)
            assertTrue("$font: $light / $regular / $heavy", regular > 0 && heavy > regular && light <= regular)
            // Полужирный при том же ползунке — жирнее обычного.
            assertTrue("$font semibold", width(font, 400, bold = true) > regular)
        }
    }

    @Test
    fun bundledFontDiffersFromSystem() {
        val system = width(AppFont.SYSTEM, 400)
        val nunito = width(AppFont.NUNITO, 400)
        assertTrue("$system vs $nunito", system > 0 && nunito > 0 && system != nunito)
    }
}
