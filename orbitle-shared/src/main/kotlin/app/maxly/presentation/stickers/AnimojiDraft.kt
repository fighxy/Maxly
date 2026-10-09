package app.maxly.presentation.stickers

import app.maxly.domain.AnimatedEmoji
import app.maxly.domain.TextSpan

/**
 * Анимодзи, вставленные в поле ввода. При отправке каждое вхождение их эмодзи
 * уходит отметкой `ANIMOJI` со смещением UTF-16.
 */
class AnimojiDraft {
    private val byEmoji = LinkedHashMap<String, AnimatedEmoji>()

    fun insert(emoji: AnimatedEmoji) {
        if (emoji.emoji.isNotEmpty()) byEmoji[emoji.emoji] = emoji
    }

    fun clear() {
        byEmoji.clear()
    }

    fun spans(text: String): List<TextSpan> {
        if (byEmoji.isEmpty() || text.isEmpty()) return emptyList()
        val keys = byEmoji.keys.sortedByDescending { it.length }
        val spans = ArrayList<TextSpan>()
        var index = 0
        while (index < text.length) {
            val key = keys.firstOrNull { text.startsWith(it, index) }
            if (key == null) {
                index++
                continue
            }
            val emoji = byEmoji.getValue(key)
            spans += TextSpan(TextSpan.Kind.ANIMOJI, index, key.length, url = emoji.lottieUrl, entityId = emoji.id)
            index += key.length
        }
        return spans
    }
}
