package app.maxly.domain

/**
 * Своё фото на обоях. Файл уже уменьшен и повёрнут по EXIF при выборе ([WallpaperScale]),
 * поэтому экран чата только читает его один раз и кладёт в кэш.
 */
data class WallpaperPhoto(
    /** Абсолютный путь к копии в личной папке приложения. */
    val path: String,
    /** Затемнение поверх фото, [WallpaperScale.MIN_DIM]…[WallpaperScale.MAX_DIM] процентов. */
    val dimPercent: Int = 0,
    /** Размыть фото, чтобы пузыри читались лучше. */
    val blur: Boolean = false,
)

/** Что выбрано для обоев конкретного чата в «Обоях» его профиля. */
sealed interface ChatWallpaperChoice {
    /** «Как в общих»: обои из «Оформления». */
    data object Global : ChatWallpaperChoice

    /** «Без обоев»: в этом чате ровный фон, даже если в «Оформлении» выбраны обои. */
    data object Plain : ChatWallpaperChoice

    /** «Своё фото…» только для этого чата. */
    data class Photo(val path: String) : ChatWallpaperChoice
}

/** Итог для чата: своё фото, ровный фон или набор из «Оформления» ([ChatWallpaper]). */
sealed interface ResolvedWallpaper {
    data class Photo(val photo: WallpaperPhoto) : ResolvedWallpaper
    data object Plain : ResolvedWallpaper
    data object Preset : ResolvedWallpaper
}

/** Размеры копии фото для обоев: уменьшение до [MAX_SIDE] по длинной стороне и поворот по EXIF. */
object WallpaperScale {
    /** Длинная сторона копии в пикселях: хватает на 4K-монитор с запасом под обрезку. */
    const val MAX_SIDE = 2560
    const val MIN_DIM = 0
    const val MAX_DIM = 60

    fun clampDim(percent: Int): Int = percent.coerceIn(MIN_DIM, MAX_DIM)

    /**
     * Размер копии для картинки [width]×[height]: длинная сторона не больше [maxSide], пропорции
     * сохраняются, маленькие картинки не растягиваются. Стороны не меньше 1.
     */
    fun target(width: Int, height: Int, maxSide: Int = MAX_SIDE): Pair<Int, Int> {
        require(width > 0 && height > 0) { "Пустая картинка: ${width}×$height" }
        val longest = maxOf(width, height)
        if (longest <= maxSide) return width to height
        val scale = maxSide.toDouble() / longest
        val w = Math.round(width * scale).toInt().coerceIn(1, maxSide)
        val h = Math.round(height * scale).toInt().coerceIn(1, maxSide)
        return w to h
    }

    /**
     * Шаг прореживания при чтении (степень двойки): самое грубое чтение, после которого длинная
     * сторона ещё не меньше [maxSide]. Остаток добирает точное уменьшение до [target].
     */
    fun sampleSize(width: Int, height: Int, maxSide: Int = MAX_SIDE): Int {
        val longest = maxOf(width, height)
        var sample = 1
        while (longest / (sample * 2) >= maxSide) sample *= 2
        return sample
    }

    /** Меняет ли ориентация EXIF (1…8) местами ширину и высоту: 5…8 — поворот на 90° или 270°. */
    fun swapsSides(exifOrientation: Int): Boolean = exifOrientation in 5..8

    /** Размер картинки после поворота по EXIF. */
    fun oriented(width: Int, height: Int, exifOrientation: Int): Pair<Int, Int> =
        if (swapsSides(exifOrientation)) height to width else width to height

    /**
     * Обрезка «по центру, без растяжения» картинки [imageW]×[imageH] под область [boxW]×[boxH]:
     * масштаб, при котором картинка закрывает всю область, и левый верхний угол видимого куска
     * в координатах картинки. Нужна для проверки, что пропорции не искажаются.
     */
    fun centerCrop(imageW: Int, imageH: Int, boxW: Int, boxH: Int): Crop {
        val scale = maxOf(boxW.toDouble() / imageW, boxH.toDouble() / imageH)
        val visibleW = boxW / scale
        val visibleH = boxH / scale
        return Crop(scale, (imageW - visibleW) / 2, (imageH - visibleH) / 2, visibleW, visibleH)
    }

    data class Crop(val scale: Double, val left: Double, val top: Double, val width: Double, val height: Double)
}
