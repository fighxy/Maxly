package app.orbitle.domain

/**
 * Что делает собеседник: поле `type` команды 65 и уведомления 129. Пустое или незнакомое
 * значение — [TEXT].
 */
enum class TypingKind(val raw: String) {
    TEXT("TEXT"),
    AUDIO("AUDIO"),
    VIDEO_MSG("VIDEO_MSG"),
    PHOTO("PHOTO"),
    VIDEO("VIDEO"),
    FILE("FILE"),
    STICKER("STICKER"),
    ;

    companion object {
        fun of(raw: String?): TypingKind = entries.firstOrNull { it.raw == raw } ?: TEXT
    }
}

/** Один собеседник с индикатором: имя (если известно), вид действия, когда он начал и его id. */
data class Typist(val name: String?, val kind: TypingKind = TypingKind.TEXT, val sinceMs: Long = 0, val userId: String = "") {
    companion object {
        /** По началу действия, при равенстве — по id. */
        val ORDER: Comparator<Typist> = compareBy<Typist> { it.sinceMs }.thenBy { it.userId }
    }
}
