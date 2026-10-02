package app.orbitle.ui.chat

import android.graphics.Paint

/** Умеет ли шрифт устройства нарисовать эмодзи: новые эмодзи старые Android показывают квадратом. */
object EmojiSupport {
    private val paint = Paint()
    private val cache = HashMap<String, Boolean>()

    @Synchronized
    fun canDraw(emoji: String): Boolean = cache.getOrPut(emoji) { paint.hasGlyph(emoji) }
}
