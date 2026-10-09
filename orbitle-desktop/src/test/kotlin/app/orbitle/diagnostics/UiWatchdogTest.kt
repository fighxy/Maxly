package app.orbitle.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Сторож окна: подтормаживание, зависание, оживление и сон компьютера. */
class UiWatchdogTest {
    private var time = 0L
    private val queue = ArrayDeque<Runnable>()
    private val events = mutableListOf<String>()
    private val dog = UiWatchdog(
        post = { queue.addLast(it) },
        now = { time },
        intervalMs = 500,
        slowMs = 1_000,
        hangMs = 5_000,
        onSlow = { events += "slow $it" },
        onHang = { events += "hang $it" },
        onRecovered = { events += "recovered $it" },
    )

    /** Окно выполняет всё, что накопилось в очереди. */
    private fun drain() {
        while (queue.isNotEmpty()) queue.removeFirst().run()
    }

    private fun step(ms: Long = 500) {
        time += ms
        dog.tick()
    }

    @Test
    fun responsiveWindowStaysQuiet() {
        repeat(10) {
            step()
            drain()
        }
        assertTrue(events.isEmpty())
        assertTrue(queue.isEmpty())
    }

    @Test
    fun slowAnswerIsReportedOnce() {
        step()
        step()
        step()
        // Пока проба не выполнена, новые не отправляются.
        assertEquals(1, queue.size)
        drain()
        assertEquals(listOf("slow 1000"), events)
    }

    @Test
    fun hangIsReportedOnceThenRecovery() {
        step()
        repeat(12) { step() }
        assertEquals(listOf("hang 5000"), events)
        drain()
        assertEquals(listOf("hang 5000", "recovered 6000"), events)
        // Следующая проба снова отвечает вовремя.
        step()
        drain()
        assertEquals(2, events.size)
    }

    @Test
    fun sleepDoesNotLookLikeHang() {
        step()
        // Компьютер спал минуту: такт пришёл сильно позже.
        step(60_000)
        step()
        assertTrue(events.isEmpty())
        // Старая проба выполнилась после сна — она забыта, новая отвечает вовремя.
        drain()
        assertTrue(events.isEmpty())
    }
}
