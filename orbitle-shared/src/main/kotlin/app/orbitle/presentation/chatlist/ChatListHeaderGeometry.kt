package app.orbitle.presentation.chatlist

/**
 * Шапка списка чатов, как на iOS: истории, поиск и папки. Поиск уезжает вместе со
 * списком, папки остаются под панелью. Истории спрятаны над поиском: список встаёт на поиск,
 * истории открывает только палец (потянуть вниз у верха), инерция останавливается на поиске.
 *
 * [top] — сколько шапки уехало вверх: 0 — истории видны целиком, [stories] — спрятаны
 * (сверху поиск), [maxTop] — уехал и поиск, папки закреплены. Всё в пикселях.
 */
data class ChatListHeaderGeometry(
    val stories: Float,
    val search: Float,
    /** Насколько истории могут выглядывать, пока у заголовка ещё стопка их аватаров. */
    val stackSlack: Float = 0f,
) {
    val maxTop: Float get() = stories + search

    /** Где стоять, чтобы истории были спрятаны: верх поиска. */
    val storiesHiddenTop: Float get() = stories

    /** Истории спрятаны (или их нет): у заголовка — стопка аватаров. */
    fun storiesHidden(top: Float): Boolean = stories <= 0f || top >= stories - stackSlack

    /** Поиск уехал: папки прижаты к панели. */
    fun foldersPinned(top: Float): Boolean = top >= maxTop - 0.5f

    /**
     * Новый [top] после движения списка на [dy] (палец вниз — плюс). Инерция, долетевшая сверху
     * до спрятанных историй, останавливается на поиске.
     */
    fun scrolled(top: Float, dy: Float, fling: Boolean): Float {
        val floor = if (fling && top >= stories - 0.5f) stories else 0f
        return (top - dy).coerceIn(minOf(floor, top), maxTop)
    }

    /** Движение остановилось посреди историй или поиска: доехать к ближнему краю. */
    fun snapTarget(top: Float): Float? {
        for ((low, high) in listOf(0f to stories, stories to maxTop)) {
            if (high - low <= 1f || top <= low + 0.5f || top >= high - 0.5f) continue
            return if (top - low < (high - low) / 2) low else high
        }
        return null
    }

    /** Высоты пересчитались (истории загрузились): спрятанные истории остаются спрятанными. */
    fun remeasured(top: Float, old: ChatListHeaderGeometry): Float {
        val shifted = if (old.storiesHidden(top)) top - old.stories + stories else top
        return shifted.coerceIn(0f, maxTop)
    }
}
