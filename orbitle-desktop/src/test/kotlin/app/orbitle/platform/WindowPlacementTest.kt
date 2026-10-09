package app.orbitle.platform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Окно открывается там, где его закрыли, но всегда так, чтобы за заголовок можно было взяться. */
class WindowPlacementTest {
    private val laptop = ScreenArea(0, 0, 1536, 864)
    private val monitor = ScreenArea(1536, 0, 2560, 1440)

    @Test
    fun firstLaunchIsCentered() {
        assertEquals(WindowStart(null, null, 1100, 760, false), WindowPlacement.start(null, listOf(laptop)))
    }

    @Test
    fun savedPlaceOnConnectedScreenIsKept() {
        val saved = WindowBounds(1700, 100, 1400, 900, maximized = true)
        assertEquals(WindowStart(1700, 100, 1400, 900, true), WindowPlacement.start(saved, listOf(laptop, monitor)))
    }

    @Test
    fun windowFromDisconnectedMonitorMovesToCenter() {
        val saved = WindowBounds(1700, 100, 1400, 900)
        val start = WindowPlacement.start(saved, listOf(laptop))
        assertNull(start.x)
        assertNull(start.y)
        // Размер ужимается до экрана, что остался.
        assertEquals(1400, start.width)
        assertEquals(864, start.height)
    }

    @Test
    fun titleBarAboveScreenIsNotReachable() {
        assertNull(WindowPlacement.start(WindowBounds(100, -200, 1000, 700), listOf(laptop)).x)
        assertEquals(100, WindowPlacement.start(WindowBounds(100, -10, 1000, 700), listOf(laptop)).x)
    }

    @Test
    fun tinySavedSizeGrowsToMinimum() {
        val start = WindowPlacement.start(WindowBounds(10, 10, 300, 200), listOf(laptop))
        assertEquals(WindowPlacement.MIN_WIDTH, start.width)
        assertEquals(WindowPlacement.MIN_HEIGHT, start.height)
    }

    @Test
    fun storeRoundTripAndBrokenValues() {
        val bounds = WindowBounds(-8, -8, 1920, 1040, maximized = true)
        assertEquals(bounds, WindowPlacementStore.decode(WindowPlacementStore.encode(bounds)))
        assertNull(WindowPlacementStore.decode(null))
        assertNull(WindowPlacementStore.decode("1,2,3"))
        assertNull(WindowPlacementStore.decode("1,2,x,4,0"))
        assertNull(WindowPlacementStore.decode("1,2,0,4,0"))
    }
}
