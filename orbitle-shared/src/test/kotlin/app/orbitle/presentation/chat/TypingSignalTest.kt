package app.orbitle.presentation.chat

import app.orbitle.domain.TypingKind
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TypingSignalTest {
    private val sent = mutableListOf<Pair<Long, TypingKind>>()

    private fun TestScope.signal() = TypingSignal(backgroundScope, clock = { testScheduler.currentTime }) { sent += testScheduler.currentTime to it }

    @Test
    fun oneCounterForAllKinds() = runTest(UnconfinedTestDispatcher()) {
        val signal = signal()
        signal.ping(TypingKind.TEXT)
        advanceTimeBy(3_000)
        signal.ping(TypingKind.STICKER)
        advanceTimeBy(3_000)
        signal.ping(TypingKind.STICKER)
        assertEquals(listOf(0L to TypingKind.TEXT, 6_000L to TypingKind.STICKER), sent)
    }

    @Test
    fun longActivityRepeatsTheFreshestKindUntilAllEnd() = runTest(UnconfinedTestDispatcher()) {
        val signal = signal()
        signal.begin("upload", TypingKind.FILE)
        advanceTimeBy(6_500)
        signal.begin("voice", TypingKind.AUDIO)
        advanceTimeBy(6_000)
        signal.end("voice")
        advanceTimeBy(6_000)
        signal.end("upload")
        advanceTimeBy(30_000)
        assertEquals(
            listOf(0L to TypingKind.FILE, 6_000L to TypingKind.FILE, 12_000L to TypingKind.AUDIO, 18_000L to TypingKind.FILE),
            sent,
        )
    }
}
