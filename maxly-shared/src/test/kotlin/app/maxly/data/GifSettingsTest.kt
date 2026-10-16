package app.maxly.data

import app.maxly.domain.GifAutoplay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GifSettingsTest {
    private class MemoryStore : PreferenceStore {
        val map = mutableMapOf<String, String>()
        override fun get(key: String) = map[key]
        override fun put(key: String, value: String) { map[key] = value }
    }

    @Test
    fun defaultsAutoplayAlwaysAndSearchOff() {
        val prefs = GifSettings(MemoryStore()).state.value
        assertEquals(GifAutoplay.ALWAYS, prefs.autoplay)
        assertFalse(prefs.gifkaSearch)
        assertFalse(GifSettings.searchAvailable(prefs))
    }

    @Test
    fun persistsAndReloads() {
        val store = MemoryStore()
        GifSettings(store).apply { setAutoplay(GifAutoplay.WIFI_ONLY); setGifkaSearch(true) }
        val reloaded = GifSettings(store).state.value
        assertEquals(GifAutoplay.WIFI_ONLY, reloaded.autoplay)
        assertTrue(GifSettings.searchAvailable(reloaded))
    }

    @Test
    fun unknownValuesFallBack() {
        val store = MemoryStore().apply { map[GifSettings.KEY_AUTOPLAY] = "sometimes"; map[GifSettings.KEY_GIFKA] = "yes" }
        val prefs = GifSettings(store).state.value
        assertEquals(GifAutoplay.ALWAYS, prefs.autoplay)
        assertFalse(prefs.gifkaSearch)
    }

    @Test
    fun autoplayGate() {
        assertTrue(GifSettings.shouldAutoplay(GifAutoplay.ALWAYS, unmetered = false))
        assertTrue(GifSettings.shouldAutoplay(GifAutoplay.WIFI_ONLY, unmetered = true))
        assertFalse(GifSettings.shouldAutoplay(GifAutoplay.WIFI_ONLY, unmetered = false))
        assertFalse(GifSettings.shouldAutoplay(GifAutoplay.NEVER, unmetered = true))
    }

    @Test
    fun sendingNeedsKey() {
        assertFalse(GifSettings.canSendFromGifka(""))
        assertFalse(GifSettings.canSendFromGifka("  "))
        assertTrue(GifSettings.canSendFromGifka("gk_live_x"))
    }
}
