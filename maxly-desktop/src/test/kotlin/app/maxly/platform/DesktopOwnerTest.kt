package app.maxly.platform

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Test

/** Окно ведёт жизненный цикл: открытый чат активен (и ставит отметки прочтения) только в RESUMED. */
@OptIn(ExperimentalCoroutinesApi::class)
class DesktopOwnerTest {
    @Test
    fun lookingWindowIsResumedOtherwiseStarted() {
        assertEquals(Lifecycle.State.RESUMED, DesktopOwner.stateOf(true))
        assertEquals(Lifecycle.State.STARTED, DesktopOwner.stateOf(false))
    }

    /** `repeatOnLifecycle` меняет состояние в `Dispatchers.Main`: в тесте это диспетчер теста. */
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun chatIsActiveOnlyWhileTheWindowIsVisibleAndFocused() = runTest {
        val window = WindowActivity(clock = { testScheduler.currentTime })
        val owner = DesktopOwner(checkThread = false)
        owner.moveTo(Lifecycle.State.STARTED)
        backgroundScope.launch { window.looking.collect { owner.moveTo(DesktopOwner.stateOf(it)) } }
        // Как ChatScreen: setActive(true) в RESUMED, setActive(false) при выходе из него.
        val active = mutableListOf<Boolean>()
        backgroundScope.launch {
            owner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
                active += true
                try {
                    awaitCancellation()
                } finally {
                    active += false
                }
            }
        }
        runCurrent()
        assertEquals(emptyList<Boolean>(), active)
        window.setFocused(true)
        runCurrent()
        assertEquals(listOf(true), active)
        // Свёрнуто: отметок нет.
        window.setMinimized(true)
        runCurrent()
        assertEquals(Lifecycle.State.STARTED, owner.lifecycle.currentState)
        // Развёрнуто снова: чат снова активен и отметит последнее видимое.
        window.setMinimized(false)
        runCurrent()
        // Окно без фокуса — тоже без отметок.
        window.setFocused(false)
        runCurrent()
        assertEquals(listOf(true, false, true, false), active)
        owner.destroy()
        owner.moveTo(Lifecycle.State.RESUMED)
        assertEquals(Lifecycle.State.DESTROYED, owner.lifecycle.currentState)
    }
}
