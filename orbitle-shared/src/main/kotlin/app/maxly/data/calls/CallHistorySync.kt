package app.maxly.data.calls

import com.maxly.core.calls.CallHistoryAction
import com.maxly.core.calls.CallHistoryItem
import com.maxly.core.calls.CallHistoryPage

/**
 * Журнал звонков `CALL_HISTORY` 163: курсор [sync] и звонки от нового к старому.
 * [loaded] `false` — 163 ещё не отвечал, пуши 165 тогда не применяются.
 */
data class CallHistoryLog(
    val loaded: Boolean = false,
    val sync: Long = 0,
    val items: List<CallHistoryItem> = emptyList(),
)

/** Итог пуша 165: новый журнал и нужно ли перечитать его запросом 163. */
data class CallHistoryPush(val log: CallHistoryLog, val resync: Boolean)

/** Правка журнала ответами 163 и пушами 165. Чистая логика, без сети. */
object CallHistorySync {
    /** Ключ звонка в журнале: `historyId`, а без него — `callId`. */
    fun key(item: CallHistoryItem): String = if (item.historyId != 0L) "h${item.historyId}" else "c${item.callId}"

    /** Ответ 163: `reset` (и первый ответ) заменяет журнал, иначе звонки добавляются поверх. */
    fun page(log: CallHistoryLog, page: CallHistoryPage): CallHistoryLog {
        val base = if (page.reset || !log.loaded) emptyList() else log.items
        return CallHistoryLog(loaded = true, sync = page.sync, items = upsert(base, page.items))
    }

    /**
     * Пуш 165. Не тот предыдущий курсор, незагруженный журнал или неизвестное действие —
     * журнал не трогается, его надо перечитать (так делает и приложение Max).
     */
    fun push(
        log: CallHistoryLog,
        sync: Long,
        prevSync: Long,
        action: CallHistoryAction?,
        items: List<CallHistoryItem>,
        historyIds: List<Long>,
    ): CallHistoryPush {
        if (!log.loaded || prevSync != log.sync || action == null) return CallHistoryPush(log, resync = true)
        val next = when (action) {
            CallHistoryAction.ADD -> upsert(log.items, items)
            CallHistoryAction.REMOVE -> {
                val gone = historyIds.toSet() + items.map { it.historyId }
                log.items.filterNot { it.historyId in gone }
            }
        }
        return CallHistoryPush(log.copy(sync = sync, items = next), resync = false)
    }

    /** Убирает звонки по id записей журнала ([CallHistoryRecords.id]). */
    fun without(log: CallHistoryLog, recordIds: Set<String>): CallHistoryLog =
        log.copy(items = log.items.filterNot { CallHistoryRecords.id(it) in recordIds })

    private fun upsert(base: List<CallHistoryItem>, fresh: List<CallHistoryItem>): List<CallHistoryItem> {
        val byKey = LinkedHashMap<String, CallHistoryItem>()
        base.forEach { byKey[key(it)] = it }
        fresh.forEach { byKey[key(it)] = it }
        return byKey.values.sortedWith(compareByDescending<CallHistoryItem> { it.time }.thenByDescending { it.historyId })
    }
}

/** Звонок журнала 163 как строка истории. */
object CallHistoryRecords {
    /**
     * Id записи: `messageId` звонка (по нему удаляет `VIDEO_CHAT_DELETE_HISTORY`), без него —
     * ключ журнала: такую запись можно убрать только с экрана.
     */
    fun id(item: CallHistoryItem): String = item.messageId?.takeIf { it != 0L }?.toString() ?: CallHistorySync.key(item)

    /**
     * Исход как у журнала 79: свой сброшенный — отменённый, отклонённый собеседником — отклонённый;
     * входящий пропущен, если его отменили, отклонили или не взяли, либо длительность известна и равна 0.
     */
    fun outcome(item: CallHistoryItem, outgoing: Boolean): app.maxly.domain.CallOutcome {
        val end = item.hangupType
        return if (outgoing) {
            when (end) {
                com.maxly.core.calls.CallEnd.REJECTED -> app.maxly.domain.CallOutcome.DECLINED
                com.maxly.core.calls.CallEnd.CANCELED, com.maxly.core.calls.CallEnd.MISSED -> app.maxly.domain.CallOutcome.CANCELLED
                else -> if (item.durationMs == 0L) app.maxly.domain.CallOutcome.CANCELLED else app.maxly.domain.CallOutcome.ANSWERED
            }
        } else {
            val missed = item.durationMs == 0L || end in setOf(com.maxly.core.calls.CallEnd.CANCELED, com.maxly.core.calls.CallEnd.REJECTED, com.maxly.core.calls.CallEnd.MISSED)
            if (missed) app.maxly.domain.CallOutcome.MISSED else app.maxly.domain.CallOutcome.ANSWERED
        }
    }

    /** Длительность: неизвестная (`durationMs` нет) — `-1`, как у iOS-клиента. */
    fun duration(item: CallHistoryItem): Long = item.durationMs ?: -1L
}
