package app.orbitle.data

import com.max.core.api.PresenceInfo

/** Присутствие человека так, как его видит приложение: время в мс и «в сети». */
object PresenceTime {
    /** Меньше этого `seen` — секунды Unix (так их шлёт сервер), больше — уже миллисекунды. */
    private const val SECONDS_LIMIT = 100_000_000_000L

    /** `seen` сервера в мс; `0`, если времени нет. */
    fun ms(seen: Long?): Long = when {
        seen == null || seen <= 0 -> 0L
        seen < SECONDS_LIMIT -> seen * 1000
        else -> seen
    }

    /** В сети ли по записи присутствия (`status` 1). */
    fun isOnline(info: PresenceInfo?): Boolean = info?.status == 1

    /** Запись `presence` из ответа сервера (`{seen?, status?}`); `null`, если её нет. */
    fun from(value: Any?): PresenceInfo? {
        val map = value as? Map<*, *> ?: return null
        return PresenceInfo((map["seen"] as? Number)?.toLong(), (map["status"] as? Number)?.toInt())
    }

    /**
     * Свежая из двух записей: [stored] из стора (пуши) и [page] из ответа со списком. Стор
     * главнее, пока страница не новее по `seen`.
     */
    fun freshest(stored: PresenceInfo?, page: PresenceInfo?): PresenceInfo? = when {
        stored == null -> page
        page == null -> stored
        ms(page.seen) > ms(stored.seen) -> page
        else -> stored
    }
}
