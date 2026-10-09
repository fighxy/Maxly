package app.maxly.ui.components

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.unit.Dp
import app.maxly.domain.PrivateModeDisplay

/** Вид приватного режима на текущем экране. Экраны, где данные открывают осознанно, ставят VISIBLE. */
val LocalPrivateMode = staticCompositionLocalOf { PrivateModeDisplay.VISIBLE }

/** Размытие в виде «Размытие»; в остальных видах ничего не меняет. */
fun Modifier.privateBlur(display: PrivateModeDisplay, radius: Dp): Modifier =
    if (display == PrivateModeDisplay.BLUR) blur(radius, BlurredEdgeTreatment.Unbounded) else this
