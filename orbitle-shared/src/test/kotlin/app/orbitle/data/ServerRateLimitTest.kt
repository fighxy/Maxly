package app.orbitle.data

import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ServerRateLimitTest {
    private var now = 1_000_000L
    private val limit = ServerRateLimit { now }

    @Test
    fun pauseGrowsWithRefusalsAndResetsOnSuccess() {
        assertNull(limit.remainingMs())
        limit.noteLimited()
        assertEquals(15_000L, limit.remainingMs())
        now += 15_000
        assertNull(limit.remainingMs())

        limit.noteLimited()
        assertEquals(30_000L, limit.remainingMs())
        now += 30_000
        limit.noteLimited()
        assertEquals(60_000L, limit.remainingMs())
        now += 60_000
        limit.noteLimited()
        limit.noteLimited()
        now += 1_000
        // Потолок — две минуты от последнего отказа.
        assertEquals(119_000L, limit.remainingMs())

        now += 119_000
        limit.noteSuccess()
        limit.noteLimited()
        assertEquals(15_000L, limit.remainingMs())
    }

    @Test
    fun readDuringPauseFailsWithoutAskingTheServer() = runBlocking {
        limit.noteLimited()
        var asked = false
        try {
            MaxCoreGateway.read(limit) { asked = true }
            fail("пауза должна отказать")
        } catch (e: CoreFailure) {
            assertTrue(ServerRateLimit.isLimit(e.key))
            assertEquals(OrbitleError.Server(OrbitleError.RATE_LIMIT_CODE), CoreErrors.map(e))
        }
        assertFalse(asked)

        now += 15_000
        assertEquals(7, MaxCoreGateway.read(limit) { 7 })
    }

    @Test
    fun openedChatReadGoesDuringThePauseAndResetsStrikes() = runBlocking {
        limit.noteLimited()
        limit.noteLimited()
        var asked = false
        assertEquals(5, MaxCoreGateway.readNow(limit) { asked = true; 5 })
        assertTrue(asked)
        // Удачное чтение сбросило счёт отказов: следующий отказ — снова короткая пауза.
        now += 120_000
        limit.noteLimited()
        assertEquals(15_000L, limit.remainingMs())
    }

    @Test
    fun rateLimitTextAsksToWait() {
        val error = OrbitleError.Server("too.many.requests")
        assertTrue(error.isRateLimit)
        assertEquals("Сервер просит подождать: слишком много запросов", error.userMessage)
        assertFalse(OrbitleError.Server("not.found").isRateLimit)
    }
}
