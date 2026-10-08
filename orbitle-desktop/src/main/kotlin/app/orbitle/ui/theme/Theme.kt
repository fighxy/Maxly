package app.orbitle.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Пузырь своих сообщений. Тот же индиго, что у акцента темы, но без затемнения под белый текст. */
val OrbitleOutgoing = Color(0xFF5C6BF5)

private val Indigo = Color(0xFF3E4AD8)
private val IndigoLight = Color(0xFFBDC2FF)

private val LightColors = lightColorScheme(
    primary = Indigo,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE0E2FF),
    onPrimaryContainer = Color(0xFF0E1460),
    inversePrimary = IndigoLight,
    secondary = Color(0xFF5C5E6A),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE2E3EA),
    onSecondaryContainer = Color(0xFF191B22),
    tertiary = Color(0xFF1F7A4D),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFC4EED6),
    onTertiaryContainer = Color(0xFF06331C),
    background = Color(0xFFF7F7F8),
    onBackground = Color(0xFF1B1B1F),
    surface = Color(0xFFF7F7F8),
    onSurface = Color(0xFF1B1B1F),
    surfaceVariant = Color(0xFFE2E2E6),
    onSurfaceVariant = Color(0xFF45464D),
    surfaceTint = Color.Transparent,
    outline = Color(0xFF76777E),
    outlineVariant = Color(0xFFC6C6CC),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
    inverseSurface = Color(0xFF303034),
    inverseOnSurface = Color(0xFFF3F0F4),
    scrim = Color.Black,
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFF2F2F4),
    surfaceContainer = Color(0xFFECECEF),
    surfaceContainerHigh = Color(0xFFE6E6EA),
    surfaceContainerHighest = Color(0xFFE0E1E5),
)

private val DarkColors = darkColorScheme(
    primary = IndigoLight,
    onPrimary = Color(0xFF12164A),
    primaryContainer = Color(0xFF2C3696),
    onPrimaryContainer = Color(0xFFE0E2FF),
    inversePrimary = Indigo,
    secondary = Color(0xFFC6C6D0),
    onSecondary = Color(0xFF2F3038),
    secondaryContainer = Color(0xFF45464E),
    onSecondaryContainer = Color(0xFFE2E3EA),
    tertiary = Color(0xFF8FD7B0),
    onTertiary = Color(0xFF003821),
    tertiaryContainer = Color(0xFF0E5133),
    onTertiaryContainer = Color(0xFFC4EED6),
    background = Color(0xFF0C0E14),
    onBackground = Color(0xFFE4E2E8),
    surface = Color(0xFF0C0E14),
    onSurface = Color(0xFFE4E2E8),
    surfaceVariant = Color(0xFF2D2F37),
    onSurfaceVariant = Color(0xFFC6C6CC),
    surfaceTint = Color.Transparent,
    outline = Color(0xFF909098),
    outlineVariant = Color(0xFF45464D),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    inverseSurface = Color(0xFFE4E2E8),
    inverseOnSurface = Color(0xFF303034),
    scrim = Color.Black,
    surfaceContainerLowest = Color(0xFF08090E),
    surfaceContainerLow = Color(0xFF14161D),
    surfaceContainer = Color(0xFF181A21),
    surfaceContainerHigh = Color(0xFF22242C),
    surfaceContainerHighest = Color(0xFF2D2F37),
)

/** Градиенты аватаров без фото: те же семь тонов, что в iOS-версии. */
object AvatarPalette {
    val gradients: List<Pair<Color, Color>> = listOf(
        Color(1.00f, 0.53f, 0.45f) to Color(0.93f, 0.33f, 0.33f),
        Color(1.00f, 0.75f, 0.40f) to Color(0.98f, 0.56f, 0.20f),
        Color(0.73f, 0.60f, 1.00f) to Color(0.55f, 0.40f, 0.93f),
        Color(0.55f, 0.87f, 0.45f) to Color(0.33f, 0.72f, 0.32f),
        Color(0.45f, 0.87f, 0.87f) to Color(0.22f, 0.70f, 0.75f),
        Color(0.47f, 0.75f, 1.00f) to Color(0.27f, 0.55f, 0.93f),
        Color(1.00f, 0.55f, 0.75f) to Color(0.90f, 0.35f, 0.58f),
    )

    fun pair(index: Int): Pair<Color, Color> = gradients[Math.floorMod(index, gradients.size)]

    /** Цвет имени автора в группе: тот же тон, что у его аватара без фото. */
    fun nameColor(index: Int): Color = pair(index).second
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun OrbitleTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialExpressiveTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        motionScheme = MotionScheme.expressive(),
        typography = Typography(),
        content = content,
    )
}
