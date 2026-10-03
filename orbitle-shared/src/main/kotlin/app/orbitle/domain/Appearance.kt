package app.orbitle.domain

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

data class AppearancePreferences(
    val textSize: TextSizeStep = TextSizeStep.STANDARD,
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val wallpaper: ChatWallpaper = ChatWallpaper.PLAIN,
)
