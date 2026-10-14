package app.maxly.domain

/** Шаг размера текста: семь шагов, стандарт — 17 пт основного текста, как в iOS-клиенте. */
enum class TextSizeStep(val bodyPointSize: Int) {
    X_SMALL(14), SMALL(15), MEDIUM(16), LARGE(17), X_LARGE(19), XX_LARGE(21), XXX_LARGE(23);

    /** Масштаб шрифтов относительно стандарта. */
    val scale: Float get() = bodyPointSize / STANDARD.bodyPointSize.toFloat()

    /** Размер относительно стандарта в процентах: 82 … 135. */
    val percent: Int get() = Math.round(bodyPointSize * 100f / STANDARD.bodyPointSize)

    /** Подпись под ползунком: `17 пт · 100 %`. */
    val caption: String get() = "$bodyPointSize\u00A0пт · $percent\u00A0%"

    companion object {
        val STANDARD = LARGE
        val maxIndex: Int get() = entries.size - 1

        /** Шаг по номеру ползунка; значения за краями прижимаются к краю. */
        fun of(index: Int): TextSizeStep = entries[index.coerceIn(0, maxIndex)]
    }
}

enum class ThemeMode(val title: String) { SYSTEM("Системная"), LIGHT("Светлая"), DARK("Тёмная") }

/** Обои за лентой. «Осень (авто)» следует теме: в светлой — светлые, в тёмной — тёмные. */
enum class ChatWallpaper(val title: String) {
    PLAIN("Без обоев"), AUTUMN_AUTO("Осень (авто)"), AUTUMN("Осень"), AUTUMN_DARK("Осень тёмная"), AUTUMN_NIGHT("Осень ночь");

    /** Какая картинка нужна в этой теме; `null` — без обоев. */
    fun image(dark: Boolean): WallpaperImage? = when (this) {
        PLAIN -> null
        AUTUMN_AUTO -> if (dark) WallpaperImage.AUTUMN_DARK else WallpaperImage.AUTUMN
        AUTUMN -> WallpaperImage.AUTUMN
        AUTUMN_DARK -> WallpaperImage.AUTUMN_DARK
        AUTUMN_NIGHT -> WallpaperImage.AUTUMN_NIGHT
    }
}

enum class WallpaperImage { AUTUMN, AUTUMN_DARK, AUTUMN_NIGHT }

/**
 * Шрифт всего интерфейса. Кроме системного — свободные (OFL) шрифты с кириллицей и плавной
 * толщиной, они лежат в приложении: [file] — имя файла без `.ttf`, [minWeight]…[maxWeight] —
 * диапазон оси толщины `wght` этого файла.
 */
enum class AppFont(val title: String, val file: String?, val minWeight: Int, val maxWeight: Int) {
    SYSTEM("Системный", null, 100, 900),
    INTER("Inter", "inter", 100, 900),
    ONEST("Onest", "onest", 100, 900),
    GOLOS("Golos Text", "golos_text", 400, 900),
    MANROPE("Manrope", "manrope", 200, 800),
    NUNITO("Nunito", "nunito", 200, 1000),
}

/**
 * Толщина текста: ползунок задаёт толщину обычного текста [base] (по умолчанию 400), остальные
 * начертания сдвигаются на столько же — полужирный остаётся заметно жирнее обычного. У системного
 * шрифта толщина ступенчатая (сотнями), у встроенных — любая в пределах оси файла.
 */
object FontWeightScale {
    const val MIN = 300
    const val MAX = 600
    const val DEFAULT = 400

    /** Блоки кода: моноширинный JetBrains Mono, ось 100…800. */
    const val MONO_FILE = "jetbrains_mono"

    fun clamp(base: Int): Int = base.coerceIn(MIN, MAX)

    /** Толщина для начертания [requested] (400 обычный, 600 полужирный…) при ползунке [base]. */
    fun axis(font: AppFont, requested: Int, base: Int): Int {
        val shifted = requested + clamp(base) - DEFAULT
        val value = if (font.file == null) Math.round(shifted / 100f) * 100 else shifted
        return value.coerceIn(font.minWeight, font.maxWeight)
    }

    /** Подпись под ползунком: «Обычный · 400». */
    fun caption(base: Int): String {
        val value = clamp(base)
        val name = when {
            value < 350 -> "Светлый"
            value < 450 -> "Обычный"
            value < 550 -> "Средний"
            else -> "Полужирный"
        }
        return "$name\u00A0· $value"
    }
}

data class AppearancePreferences(
    val textSize: TextSizeStep = TextSizeStep.STANDARD,
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val wallpaper: ChatWallpaper = ChatWallpaper.PLAIN,
    val font: AppFont = AppFont.SYSTEM,
    /** Толщина обычного текста, [FontWeightScale.MIN]…[FontWeightScale.MAX]. */
    val fontWeight: Int = FontWeightScale.DEFAULT,
) {
    /** Строка «Шрифт ›» в «Оформлении»: «Inter, 17 пт». */
    val fontSummary: String get() = "${font.title}, ${textSize.bodyPointSize}\u00A0пт"
}
