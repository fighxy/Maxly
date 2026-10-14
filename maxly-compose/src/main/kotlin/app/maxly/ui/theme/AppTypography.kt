package app.maxly.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import app.maxly.domain.AppFont
import app.maxly.domain.FontWeightScale

/** Файл шрифта платформы ([file] без `.ttf`) в начертании [weight] с осью толщины [axis]. */
fun interface FontSource {
    fun font(file: String, weight: FontWeight, axis: Int): Font
}

/** Начертания, которые просит интерфейс: 100…900. */
private val weights = (1..9).map { FontWeight(it * 100) }

/**
 * Семейство шрифта [font] при ползунке толщины [base]: каждое начертание (обычный, полужирный…)
 * берёт ту же переменную гарнитуру со сдвинутой осью `wght` ([FontWeightScale.axis]). Системный —
 * `null`: его толщину сдвигает только [appTypography].
 */
fun appFontFamily(font: AppFont, base: Int, source: FontSource): FontFamily? {
    val file = font.file ?: return null
    return FontFamily(weights.map { source.font(file, it, FontWeightScale.axis(font, it.weight, base)) })
}

/** Моноширинный для блоков кода: JetBrains Mono, тоже с ползунком толщины. */
fun monoFontFamily(base: Int, source: FontSource): FontFamily =
    FontFamily(weights.map { source.font(FontWeightScale.MONO_FILE, it, (it.weight + FontWeightScale.clamp(base) - FontWeightScale.DEFAULT).coerceIn(100, 800)) })

/**
 * Типографика Material с семейством [family] у всех стилей. У системного шрифта ([family] `null`)
 * толщина стилей сдвигается сотнями ([FontWeightScale.axis]); у встроенного сдвиг уже в семействе.
 */
fun appTypography(family: FontFamily?, font: AppFont, base: Int): Typography {
    val defaults = Typography()
    fun TextStyle.styled(): TextStyle {
        if (family != null) return copy(fontFamily = family)
        val weight = fontWeight?.weight ?: FontWeight.Normal.weight
        return copy(fontWeight = FontWeight(FontWeightScale.axis(font, weight, base)))
    }
    return Typography(
        displayLarge = defaults.displayLarge.styled(),
        displayMedium = defaults.displayMedium.styled(),
        displaySmall = defaults.displaySmall.styled(),
        headlineLarge = defaults.headlineLarge.styled(),
        headlineMedium = defaults.headlineMedium.styled(),
        headlineSmall = defaults.headlineSmall.styled(),
        titleLarge = defaults.titleLarge.styled(),
        titleMedium = defaults.titleMedium.styled(),
        titleSmall = defaults.titleSmall.styled(),
        bodyLarge = defaults.bodyLarge.styled(),
        bodyMedium = defaults.bodyMedium.styled(),
        bodySmall = defaults.bodySmall.styled(),
        labelLarge = defaults.labelLarge.styled(),
        labelMedium = defaults.labelMedium.styled(),
        labelSmall = defaults.labelSmall.styled(),
    )
}

/** Источник встроенных шрифтов платформы: экран «Шрифт» рисует ими названия. */
val LocalFontSource = staticCompositionLocalOf<FontSource?> { null }

/** Семейство блоков кода (моноширинный); без него — системный моноширинный. */
val LocalMonoFamily = staticCompositionLocalOf<FontFamily> { FontFamily.Monospace }
