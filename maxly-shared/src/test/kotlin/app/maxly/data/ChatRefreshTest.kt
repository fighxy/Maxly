package app.maxly.data

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ChatRefreshTest {
    @Test
    fun refreshTimeoutReleasesTheLock() = runTest {
        val gate = RefreshGate("тест", timeoutMs = 30_000)
        try {
            gate.run { awaitCancellation() }
            fail("ожидался предел времени")
        } catch (e: RefreshTimeoutException) {
        }
        assertFalse(gate.isBusy)
        var ran = false
        assertTrue(gate.run { ran = true })
        assertTrue(ran)
    }

    @Test
    fun failedBlockReleasesTheLock() = runTest {
        val gate = RefreshGate("тест")
        runCatching { gate.run { error("сбой") } }
        assertFalse(gate.isBusy)
        assertTrue(gate.run { })
    }

    @Test
    fun failedUserIdsAreRetried() = runTest {
        val requests = UserRequests()
        val calls = mutableListOf<List<Long>>()
        var fail = true
        val loader: suspend (List<Long>) -> Unit = { ids -> calls += ids; if (fail) error("сеть") }
        requests.load(listOf(1L, 2L), loader = loader)
        assertFalse(requests.isRequested(1L))
        fail = false
        requests.load(listOf(1L, 2L), loader = loader)
        assertTrue(requests.isRequested(1L))
        // Загруженные не запрашиваются повторно.
        requests.load(listOf(1L, 2L), loader = loader)
        assertEquals(listOf(listOf(1L, 2L), listOf(1L, 2L)), calls)
    }

    @Test
    fun onlyFailedChunkIsReleased() = runTest {
        val requests = UserRequests()
        requests.load(listOf(1L, 2L, 3L), chunk = 2) { ids -> if (3L in ids) error("сеть") }
        assertTrue(requests.isRequested(1L))
        assertFalse(requests.isRequested(3L))
    }
}
