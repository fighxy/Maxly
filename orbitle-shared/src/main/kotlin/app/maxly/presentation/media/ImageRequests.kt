package app.maxly.presentation.media

import com.maxly.core.media.ImageShape
import com.maxly.core.media.ImageSizes
import kotlin.math.ceil

/**
 * Адрес картинки нужного размера. Лестницу знает ядро ([ImageSizes]): первый шаг,
 * который не меньше «размер в точках × плотность». Полноэкранный просмотр и файл
 * на диске остаются без `fn`.
 */
object ImageRequests {
    /** Аватар: `sqr_N`. [points] — сторона в dp. */
    fun square(url: String?, points: Float, density: Float): String? =
        sized(url, ImageShape.SQUARE, points, density)

    /** Фото в ленте: `w_N`. [points] — ширина в dp. */
    fun width(url: String?, points: Float, density: Float): String? =
        sized(url, ImageShape.WIDTH, points, density)

    /** Полноэкранный просмотр: исходный адрес, без `fn`. */
    fun original(url: String?): String? = url

    fun sized(url: String?, shape: ImageShape, points: Float, density: Float, fullScreen: Boolean = false): String? {
        if (url.isNullOrBlank() || fullScreen || isLocal(url)) return url
        val scale = if (density.isFinite() && density > 1f) density else 1f
        val pixels = ceil(points.coerceAtLeast(0f).toDouble() * scale).toInt()
        return ImageSizes.sizedUrl(url, shape, pixels)
    }

    /** Файл устройства и содержимое контент-провайдера размером не режем. */
    fun isLocal(url: String): Boolean {
        val lower = url.lowercase()
        return lower.startsWith("file:") || lower.startsWith("content:")
    }
}
