package app.maxly.presentation.photo

import kotlin.math.pow
import kotlin.math.roundToInt

/** Значения -1…1; виньетка, зерно, резкость и размытие — 0…1. */
data class PhotoAdjustments(
    val exposure: Float = 0f, val brightness: Float = 0f, val contrast: Float = 0f,
    val saturation: Float = 0f, val warmth: Float = 0f, val shadows: Float = 0f,
    val highlights: Float = 0f, val fade: Float = 0f, val vignette: Float = 0f,
    val grain: Float = 0f, val sharpen: Float = 0f, val blur: Float = 0f,
    val curves: List<List<Float>> = List(4) { listOf(0f, .25f, .5f, .75f, 1f) },
) {
    val isDefault: Boolean get() = this == PhotoAdjustments()
    fun processor(): PhotoColorProcessor = PhotoColorProcessor(this)
}

/** LUT кривых и экспозиция рассчитываются один раз на весь кадр. */
class PhotoColorProcessor(private val values: PhotoAdjustments) {
    private val exposure = 2f.pow(values.exposure * 2)
    private val curves = values.curves.map { points -> FloatArray(256) { i ->
        val x = i / 255f * 4; val segment = x.toInt().coerceAtMost(3); val t = x - segment
        val p0 = points[(segment - 1).coerceAtLeast(0)]; val p1 = points[segment]
        val p2 = points[segment + 1]; val p3 = points[(segment + 2).coerceAtMost(4)]
        // Кубическая интерполяция с линейными касательными у концов.
        val m1 = if (segment == 0) p2 - p1 else (p2 - p0) / 2
        val m2 = if (segment == 3) p2 - p1 else (p3 - p1) / 2
        ((2*t*t*t - 3*t*t + 1)*p1 + (t*t*t - 2*t*t + t)*m1 + (-2*t*t*t + 3*t*t)*p2 + (t*t*t - t*t)*m2).coerceIn(0f, 1f)
    } }

    fun pixel(argb: Int, x: Int, y: Int, width: Int, height: Int): Int {
        var r = ((argb ushr 16) and 255) / 255f * exposure + values.brightness * .25f
        var g = ((argb ushr 8) and 255) / 255f * exposure + values.brightness * .25f
        var b = (argb and 255) / 255f * exposure + values.brightness * .25f
        val luminance = (.299f*r + .587f*g + .114f*b).coerceIn(0f, 1f)
        val tone = values.shadows * (1-luminance)*(1-luminance) * .35f + values.highlights*luminance*luminance*.35f
        val c = 1 + values.contrast * .75f; val sat = 1 + values.saturation
        r = ((luminance + (r-luminance)*sat + tone - .5f)*c + .5f + values.warmth*.08f)
        g = ((luminance + (g-luminance)*sat + tone - .5f)*c + .5f)
        b = ((luminance + (b-luminance)*sat + tone - .5f)*c + .5f - values.warmth*.08f)
        val dx = (x + .5f) / width * 2 - 1; val dy = (y + .5f) / height * 2 - 1
        val shade = 1 - values.vignette * ((dx*dx + dy*dy) / 2).coerceIn(0f, 1f) * .8f
        // Детерминированный шум: одинаковый результат повторного рендера.
        val hash = (x * 374761393 + y * 668265263) xor ((x * 374761393 + y * 668265263) ushr 13)
        val noise = ((hash and 255) / 255f - .5f) * values.grain * .18f
        fun channel(v: Float, index: Int): Int {
            val colored = curves[index][(v.coerceIn(0f,1f)*255).roundToInt()]
            val curved = curves[0][(colored*255).roundToInt()]
            val faded = curved * (1-values.fade*.35f) + values.fade*.15f
            return ((faded * shade + noise)*255).roundToInt().coerceIn(0,255)
        }
        return (argb and -0x1000000) or (channel(r,1) shl 16) or (channel(g,2) shl 8) or channel(b,3)
    }
}

object PhotoPixels {
    /** Разделимый box blur O(w*h), radius соответствует масштабу кадра. */
    fun blur(pixels: IntArray, width: Int, height: Int, radius: Int): IntArray {
        if (radius < 1) return pixels.copyOf()
        val temporary = IntArray(pixels.size); val output = IntArray(pixels.size)
        fun pass(input: IntArray, target: IntArray, horizontal: Boolean) {
            val length = if (horizontal) width else height; val lines = if (horizontal) height else width
            val divisor = radius * 2 + 1
            for (line in 0 until lines) {
                fun index(position: Int) = if (horizontal) line * width + position.coerceIn(0,length-1) else position.coerceIn(0,length-1) * width + line
                var r = 0; var g = 0; var b = 0
                for (i in -radius..radius) { val p = input[index(i)]; r += (p ushr 16) and 255; g += (p ushr 8) and 255; b += p and 255 }
                for (i in 0 until length) {
                    target[index(i)] = -0x1000000 or ((r / divisor) shl 16) or ((g / divisor) shl 8) or (b / divisor)
                    val remove = input[index(i-radius)]; val add = input[index(i+radius+1)]
                    r += ((add ushr 16) and 255) - ((remove ushr 16) and 255)
                    g += ((add ushr 8) and 255) - ((remove ushr 8) and 255)
                    b += (add and 255) - (remove and 255)
                }
            }
        }
        pass(pixels, temporary, true); pass(temporary, output, false)
        return output
    }

    fun adjust(pixels: IntArray, size: PhotoSize, values: PhotoAdjustments): IntArray {
        val processor = values.processor()
        var result = IntArray(pixels.size) { i -> processor.pixel(pixels[i], i % size.width, i / size.width, size.width, size.height) }
        if (values.sharpen > 0) {
            val soft = blur(result, size.width, size.height, maxOf(1, (size.shortest * .0015f).roundToInt()))
            result = IntArray(result.size) { i ->
                fun channel(shift: Int): Int { val p = (result[i] ushr shift) and 255; val s = (soft[i] ushr shift) and 255; return (p + (p-s)*values.sharpen*2).roundToInt().coerceIn(0,255) }
                -0x1000000 or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
            }
        }
        if (values.blur > 0) result = blur(result, size.width, size.height, maxOf(1, (size.shortest * .025f * values.blur).roundToInt()))
        return result
    }
}
