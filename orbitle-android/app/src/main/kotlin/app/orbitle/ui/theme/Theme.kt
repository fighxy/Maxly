package app.orbitle.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Пузырь своих сообщений (как `orbitleOutgoing` в iOS-версии). */
val OrbitleOutgoing = Color(0xFF5C6BF5)

/**
 * Подсветка системных кнопок и надписей (`primary`): глубокий графит в светлой теме, серебро
 * в тёмной — как `orbitleAccent` в iOS-версии.
 */
val OrbitleGraphite = Color(0xFF212327)
val OrbitleSilver = Color(0xFFCCD0D6)

private val LightColors = lightColorScheme(
    primary = OrbitleGraphite,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE3E4E7),
    onPrimaryContainer = Color(0xFF17181B),
    secondary = Color(0xFF5D5F65),
    secondaryContainer = Color(0xFFE3E4E7),
    onSecondaryContainer = Color(0xFF17181B),
    tertiary = Color(0xFF2EA66B),
    background = Color(0xFFFBF8FF),
    surface = Color(0xFFFBF8FF),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFF5F2FA),
    surfaceContainer = Color(0xFFEFEDF4),
    surfaceContainerHigh = Color(0xFFE9E7EF),
    surfaceContainerHighest = Color(0xFFE3E1E9),
    error = Color(0xFFBA1A1A),
)

private val DarkColors = darkColorScheme(
    primary = OrbitleSilver,
    onPrimary = Color(0xFF15171A),
    primaryContainer = Color(0xFF3A3D43),
    onPrimaryContainer = Color(0xFFE4E6EA),
    secondary = Color(0xFFC3C6CC),
    secondaryContainer = Color(0xFF3A3D43),
    onSecondaryContainer = Color(0xFFE4E6EA),
    tertiary = Color(0xFF6FDBA0),
    background = Color(0xFF0C0E14),
    surface = Color(0xFF0C0E14),
    surfaceContainerLowest = Color(0xFF08090E),
    surfaceContainerLow = Color(0xFF14161D),
    surfaceContainer = Color(0xFF181A21),
    surfaceContainerHigh = Color(0xFF22242C),
    surfaceContainerHighest = Color(0xFF2D2F37),
    error = Color(0xFFFFB4AB),
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

@Composable
fun OrbitleTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = Typography(),
        content = content,
    )
}
