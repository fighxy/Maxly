package app.maxly.presentation.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaViewerRulesTest {
    @Test
    fun chromeHidesOnlyWhilePlaying() {
        val chrome = MediaViewerChrome()
        assertTrue(chrome.shouldAutoHide(playing = true, scrubbing = false, menuOpen = false))
        assertFalse(chrome.shouldAutoHide(playing = false, scrubbing = false, menuOpen = false))
        assertFalse(chrome.shouldAutoHide(playing = true, scrubbing = true, menuOpen = false))
        chrome.toggle()
        assertFalse(chrome.visible)
        chrome.playbackStopped()
        assertTrue(chrome.visible)
    }

    @Test
    fun doubleTapsAddUpAndClamp() {
        val taps = SeekTapAccumulator()
        assertEquals(false, SeekTapAccumulator.side(10f, 300f))
        assertEquals(true, SeekTapAccumulator.side(290f, 300f))
        assertNull(SeekTapAccumulator.side(150f, 300f))
        assertEquals(SeekTapAccumulator.Seek(40_000, 10, true), taps.tap(true, 0, 30_000, 100_000))
        val second = taps.tap(true, 500, 40_000, 100_000)
        assertEquals(20, second.totalSeconds)
        assertEquals(50_000L, second.targetMs)
        assertEquals(10, taps.tap(true, 2_000, 50_000, 100_000).totalSeconds)
        assertEquals(SeekTapAccumulator.Seek(0, 10, false), taps.tap(false, 2_300, 4_000, 100_000))
        assertEquals(100_000L, taps.tap(true, 5_000, 95_000, 100_000).targetMs)
        assertTrue(taps.isActive(5_500))
        assertFalse(taps.isActive(6_000))
    }

    @Test
    fun dismissByDistanceOrFlick() {
        assertFalse(MediaDismissRule.shouldClose(80f, 100f, 800f))
        assertTrue(MediaDismissRule.shouldClose(130f, 0f, 800f))
        assertTrue(MediaDismissRule.shouldClose(-130f, 0f, 800f))
        assertTrue(MediaDismissRule.shouldClose(60f, 1_200f, 800f))
        assertFalse(MediaDismissRule.shouldClose(60f, -1_200f, 800f))
        assertEquals(1f, MediaDismissRule.backgroundAlpha(0f, 800f))
        assertEquals(0.2f, MediaDismissRule.backgroundAlpha(800f, 800f))
    }

    @Test
    fun labels() {
        assertEquals("1×", PlaybackSpeed.label(1f))
        assertEquals("1,5×", PlaybackSpeed.label(1.5f))
        assertEquals("1,25×", PlaybackSpeed.label(1.25f))
        assertEquals("0:07", MediaTimeText.clock(7_000))
        assertEquals("1:02:03", MediaTimeText.clock(3_723_000))
        assertEquals("-0:42", MediaTimeText.remaining(20_000, 62_000))
        assertEquals("37 %", MediaTimeText.download(0.37f))
        assertEquals("12,5 из 50,0 МБ", MediaTimeText.download(0.25f, 50L * 1_048_576))
    }

    @Test
    fun heroFitsInterpolatesAndReturnsOnlyIntoVisibleTiles() {
        val screen = HeroRect(0f, 0f, 400f, 800f)
        assertEquals(HeroRect(0f, 300f, 400f, 200f), MediaHeroGeometry.fit(2f, screen))
        assertEquals(HeroRect(100f, 0f, 200f, 800f), MediaHeroGeometry.fit(0.25f, screen))
        val tile = HeroRect(100f, 500f, 100f, 100f)
        val full = HeroRect(0f, 200f, 400f, 400f)
        assertEquals(tile, MediaHeroGeometry.interpolate(tile, full, 0f))
        assertEquals(full, MediaHeroGeometry.interpolate(tile, full, 1f))
        assertEquals(HeroRect(50f, 350f, 250f, 250f), MediaHeroGeometry.interpolate(tile, full, 0.5f))
        assertTrue(MediaHeroGeometry.canReturn(HeroRect(10f, 100f, 200f, 200f), screen))
        assertFalse(MediaHeroGeometry.canReturn(HeroRect(10f, 750f, 200f, 200f), screen))
        assertFalse(MediaHeroGeometry.canReturn(HeroRect(10f, 900f, 200f, 200f), screen))
    }
}
