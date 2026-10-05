package app.orbitle.presentation.chat

import app.orbitle.data.HistorySpan
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import java.util.concurrent.ConcurrentHashMap

/**
 * Куски истории чата, про которые известно, что внутри нет пропусков: каждая страница сервера
 * непрерывна, соседние и перекрывающиеся куски сливаются. Кусок, доходящий до свежих сообщений,
 * — живая лента (верх [Long.MAX_VALUE]); остальные — окна переходов к далёким сообщениям.
 *
 * Куски живут дольше экрана чата ([of]): вернувшись в чат, лента сразу знает, какие из
 * сообщений стора идут подряд.
 */
class HistoryRanges {
    private val ranges = ArrayList<LongRange>()
    /** Начало истории чата (мс): раньше сообщений нет. */
    private var beginning: Long? = null

    @Synchronized
    fun add(from: Long, to: Long) {
        if (from > to) return
        var merged = from..to
        val rest = ArrayList<LongRange>()
        for (range in ranges) {
            if (range.last >= merged.first - 1 && range.first <= merged.last + 1) {
                merged = minOf(range.first, merged.first)..maxOf(range.last, merged.last)
            } else {
                rest += range
            }
        }
        rest += merged
        rest.sortBy { it.first }
        ranges.clear()
        ranges += rest
    }

    /** Свежая страница: от её самого старого сообщения до свежих. */
    fun addLatest(span: HistorySpan) {
        add(span.oldestMs, Long.MAX_VALUE)
        if (span.reachedOldest) markBeginning(span.oldestMs)
    }

    @Synchronized
    fun markBeginning(at: Long) {
        beginning = minOf(beginning ?: at, at)
    }

    /** Живая лента; `null`, пока свежая страница не пришла. */
    @Synchronized
    fun live(): LongRange? = ranges.lastOrNull()?.takeIf { it.last == Long.MAX_VALUE }

    /** Кусок, в котором лежит момент [time]. */
    @Synchronized
    fun around(time: Long): LongRange? = ranges.firstOrNull { time in it }

    /** Кусок [range] начинается с начала истории. */
    @Synchronized
    fun startsAtBeginning(range: LongRange): Boolean = beginning?.let { range.first <= it } == true

    companion object {
        private val all = ConcurrentHashMap<String, HistoryRanges>()

        /** Куски чата на время работы приложения. */
        fun of(chatId: String): HistoryRanges = all.getOrPut(chatId) { HistoryRanges() }

        /** Выход из аккаунта: куски прежнего не годятся. */
        fun clear() = all.clear()
    }
}

/**
 * Место в ленте, к которому вернуться, открыв чат снова: строка у низа экрана и её сдвиг.
 * Внизу ленты место не хранится: чат откроется на свежих, как в Telegram.
 */
data class ScrollPlace(val key: String, val offset: Int)

/** Места в лентах чатов на время работы приложения. */
object ScrollMemory {
    private val places = ConcurrentHashMap<String, ScrollPlace>()

    fun get(chatId: String): ScrollPlace? = places[chatId]

    fun put(chatId: String, place: ScrollPlace?) {
        if (place == null) places.remove(chatId) else places[chatId] = place
    }

    fun clear() = places.clear()
}

/**
 * Куда прокрутить ленту. Экран выполняет запрос один раз и снимает его ([ChatViewModel.consumeScroll]).
 * [token] отличает повтор того же запроса.
 */
data class ScrollRequest(val target: Target, val token: Int) {
    sealed interface Target {
        /** К свежим сообщениям: прыжок, если далеко, затем плавно. */
        data object Bottom : Target

        /** «Непрочитанные сообщения» у верха экрана. */
        data class Unread(val key: String) : Target

        /** Сообщение посередине экрана, с подсветкой ([highlight]). */
        data class Message(val key: String, val highlight: Boolean) : Target

        /** Прежнее место при возврате в чат. */
        data class Place(val place: ScrollPlace) : Target
    }
}

/**
 * Какие сообщения стора видит лента: живая лента (свежие и непрерывная история под ними) или окно
 * вокруг сообщения, к которому перешли. Сообщения вне куска не показываются: между ними в
 * истории дыра. Пока свежая страница не пришла, видно всё, что есть.
 */
internal object TimelineFilter {
    fun visible(history: List<Message>, ranges: HistoryRanges, jumpTime: Long?): List<Message> {
        val range = if (jumpTime != null) ranges.around(jumpTime) else ranges.live()
        range ?: return if (jumpTime != null) emptyList() else history
        // Свои ещё не ушедшие сообщения — у живой ленты, внизу.
        return history.filter { it.timeMs in range || (jumpTime == null && it.status != MessageStatus.SENT) }
    }
}

/**
 * Первое непрочитанное: первое чужое сообщение новее своей отметки прочтения [readMarkMs] (как в
 * Komet). Без отметки — по счётчику [unread] среди последних чужих ([unreadAnchor]).
 */
internal fun firstUnread(history: List<Message>, readMarkMs: Long, unread: Int, isOutgoing: (Message) -> Boolean, complete: Boolean): String? {
    if (unread <= 0) return null
    if (readMarkMs > 0) {
        history.firstOrNull { it.timeMs > readMarkMs && !isOutgoing(it) && !it.isService }?.let { return it.id }
    }
    return unreadAnchor(history, unread, isOutgoing, complete)
}
