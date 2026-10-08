package app.orbitle.data

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GhostModeRepositoryTest {
    private class MapStore(val values: MutableMap<String, String> = mutableMapOf()) : PreferenceStore {
        var writes = 0
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) {
            writes++
            values[key] = value
        }
    }

    @Test
    fun `both flags are off until switched on and survive a new instance`() {
        val store = MapStore()
        val repo = LocalGhostModeRepository(store)
        assertFalse(repo.ghostMode.value)
        assertFalse(repo.hideReadReceipts.value)
        repo.setGhostMode(true)
        assertTrue(repo.ghostMode.value)
        assertEquals("true", store.values[LocalGhostModeRepository.KEY_GHOST])
        assertTrue(LocalGhostModeRepository(store).ghostMode.value)
        repo.setGhostMode(false)
        assertFalse(LocalGhostModeRepository(store).ghostMode.value)
    }

    @Test
    fun `read receipts flag is independent of ghost mode`() {
        val store = MapStore()
        val repo = LocalGhostModeRepository(store)
        repo.setHideReadReceipts(true)
        assertTrue(repo.hideReadReceipts.value)
        assertFalse(repo.ghostMode.value)
        val again = LocalGhostModeRepository(store)
        assertTrue(again.hideReadReceipts.value)
        assertFalse(again.ghostMode.value)
        repo.setGhostMode(true)
        repo.setHideReadReceipts(false)
        assertTrue(LocalGhostModeRepository(store).ghostMode.value)
        assertFalse(LocalGhostModeRepository(store).hideReadReceipts.value)
    }

    @Test
    fun `the same value is not written again`() {
        val store = MapStore()
        val repo = LocalGhostModeRepository(store)
        repo.setGhostMode(false)
        repo.setHideReadReceipts(false)
        assertEquals(0, store.writes)
        repo.setGhostMode(true)
        repo.setGhostMode(true)
        assertEquals(1, store.writes)
    }

    @Test
    fun `an unknown stored value reads as off`() {
        val store = MapStore(mutableMapOf(LocalGhostModeRepository.KEY_GHOST to "yes", LocalGhostModeRepository.KEY_READ_RECEIPTS to "1"))
        assertFalse(LocalGhostModeRepository(store).ghostMode.value)
        assertFalse(LocalGhostModeRepository(store).hideReadReceipts.value)
    }

    @Test
    fun `the stub knows nothing about the own presence`() = runTest {
        assertNull(LocalGhostModeRepository(MapStore()).checkOwnPresence())
    }

    @Test
    fun `own presence switch is on by default and kept apart from the core flags`() {
        val store = MapStore()
        val settings = OwnPresenceSettings(store)
        assertTrue(settings.shown.value)
        settings.setShown(false)
        assertEquals("false", store.values[OwnPresenceSettings.KEY_SHOWN])
        assertFalse(OwnPresenceSettings(store).shown.value)
        assertFalse(LocalGhostModeRepository(store).ghostMode.value)
        settings.setShown(true)
        assertTrue(OwnPresenceSettings(store).shown.value)
    }
}
