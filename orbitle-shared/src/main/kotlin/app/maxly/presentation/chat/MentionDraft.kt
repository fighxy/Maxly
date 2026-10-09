package app.maxly.presentation.chat

import app.maxly.domain.TextSpan

/**
 * Упоминания, вставленные в поле ввода.
 * При отправке каждое вхождение `@имя` уходит отметкой `USER_MENTION` со смещением UTF-16
 * уже по той строке, которая уходит на сервер.
 */
class MentionDraft {
    private val tokens = ArrayList<Pair<String, String>>()

    fun insert(token: String, userId: String) {
        if (token.isNotEmpty() && userId.isNotEmpty()) tokens += token to userId
    }

    fun clear() {
        tokens.clear()
    }

    /** Убрать отметки, чьего текста в поле уже нет. */
    fun retainPresent(text: String) {
        tokens.retainAll { text.contains(it.first) }
    }

    fun spans(text: String): List<TextSpan> {
        if (tokens.isEmpty() || text.isEmpty()) return emptyList()
        val userOf = LinkedHashMap<String, String>()
        for ((token, userId) in tokens) if (token !in userOf) userOf[token] = userId
        val keys = userOf.keys.sortedByDescending { it.length }
        val spans = ArrayList<TextSpan>()
        var index = 0
        while (index < text.length) {
            val key = keys.firstOrNull { text.startsWith(it, index) }
            if (key == null) {
                index++
                continue
            }
            spans += TextSpan(TextSpan.Kind.MENTION, index, key.length, userId = userOf[key])
            index += key.length
        }
        return spans
    }
}
