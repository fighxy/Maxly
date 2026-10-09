package app.maxly.data

import com.max.core.api.PresenceInfo
import com.max.core.api.PresenceStatus
import com.max.core.media.HttpResponse
import com.max.core.media.MediaHttp
import com.max.core.transport.ConnectionFactory
import com.max.shared.InMemoryKeyValueStore
import com.max.shared.MaxClient
import com.max.shared.MaxClientConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** Флаги ядра над настоящим [MaxClient] без сети: соединение не открывается, всё в памяти. */
@OptIn(ExperimentalCoroutinesApi::class)
class GhostModeRepositoryTest {
    private class MapStore(val values: MutableMap<String, String> = mutableMapOf()) : PreferenceStore {
        val removed = mutableListOf<String>()
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) {
            values[key] = value
        }
        override fun remove(key: String) {
            removed += key
            values.remove(key)
        }
    }

    private val coreStore = InMemoryKeyValueStore()
    private val scope = CoroutineScope(UnconfinedTestDispatcher())

    /** Клиент ядра без сети; хранилище ядра общее, как у одного устройства между запусками. */
    private fun client(): MaxClient = MaxClient(
        MaxClientConfig(namespace = "test"),
        keyValueStore = coreStore,
        connectionFactory = ConnectionFactory { _, _, _, _ -> throw IOException("offline") },
        mediaHttp = MediaHttp { _, _, _, _, _ -> HttpResponse(500, ByteArray(0)) },
    )

    @After
    fun tearDown() {
        scope.cancel()
    }

    @Test
    fun `flags come from the core and follow its changes from anywhere`() {
        val client = client()
        val repo = CoreGhostModeRepository(client, scope)
        assertFalse(repo.ghostMode.value)
        assertFalse(repo.hideReadReceipts.value)
        repo.setGhostMode(true)
        assertTrue(client.ghostMode)
        assertTrue(repo.ghostMode.value)
        assertFalse(client.hideReadReceipts)
        // Смена прямо в ядре, не через репозиторий.
        client.hideReadReceipts = true
        assertTrue(repo.hideReadReceipts.value)
        client.ghostMode = false
        assertFalse(repo.ghostMode.value)
        assertTrue(repo.hideReadReceipts.value)
    }

    @Test
    fun `flags are kept by the core across runs`() {
        val first = CoreGhostModeRepository(client(), scope)
        first.setGhostMode(true)
        first.setHideReadReceipts(true)
        val again = CoreGhostModeRepository(client(), scope)
        assertTrue(again.ghostMode.value)
        assertTrue(again.hideReadReceipts.value)
        again.setHideReadReceipts(false)
        assertFalse(CoreGhostModeRepository(client(), scope).hideReadReceipts.value)
        assertTrue(CoreGhostModeRepository(client(), scope).ghostMode.value)
    }

    @Test
    fun `old local flags move to the core once and their keys go away`() {
        val legacy = MapStore(
            mutableMapOf(
                CoreGhostModeRepository.LEGACY_GHOST to "true",
                CoreGhostModeRepository.LEGACY_READ_RECEIPTS to "true",
                OwnPresenceSettings.KEY_SHOWN to "false",
            ),
        )
        val client = client()
        val repo = CoreGhostModeRepository(client, scope, legacy)
        assertTrue(client.ghostMode)
        assertTrue(client.hideReadReceipts)
        assertTrue(repo.ghostMode.value)
        assertTrue(repo.hideReadReceipts.value)
        assertNull(legacy.values[CoreGhostModeRepository.LEGACY_GHOST])
        assertNull(legacy.values[CoreGhostModeRepository.LEGACY_READ_RECEIPTS])
        // «Показывать мой онлайн» остаётся своим ключом.
        assertEquals("false", legacy.values[OwnPresenceSettings.KEY_SHOWN])
        // Второй запуск ничего не переносит: выключенный в ядре флаг остаётся выключенным.
        client.ghostMode = false
        CoreGhostModeRepository(client, scope, legacy)
        assertFalse(client.ghostMode)
        assertEquals(2, legacy.removed.size)
    }

    @Test
    fun `old flags that were off do not touch the core, flags on in the core stay on`() {
        val client = client()
        client.hideReadReceipts = true
        val legacy = MapStore(
            mutableMapOf(
                CoreGhostModeRepository.LEGACY_GHOST to "false",
                CoreGhostModeRepository.LEGACY_READ_RECEIPTS to "false",
            ),
        )
        CoreGhostModeRepository(client, scope, legacy)
        assertFalse(client.ghostMode)
        assertTrue(client.hideReadReceipts)
        assertTrue(legacy.values.isEmpty())
        assertEquals(listOf(CoreGhostModeRepository.LEGACY_GHOST, CoreGhostModeRepository.LEGACY_READ_RECEIPTS), legacy.removed)
    }

    @Test
    fun `migration without the old keys writes nothing`() {
        val legacy = MapStore()
        CoreGhostModeRepository(client(), scope, legacy)
        assertTrue(legacy.removed.isEmpty())
    }

    @Test
    fun `a store without removal blanks the key and it is not migrated again`() {
        val values = mutableMapOf(CoreGhostModeRepository.LEGACY_GHOST to "true")
        val plain = object : PreferenceStore {
            override fun get(key: String) = values[key]
            override fun put(key: String, value: String) {
                values[key] = value
            }
        }
        val client = client()
        CoreGhostModeRepository(client, scope, plain)
        assertTrue(client.ghostMode)
        assertEquals("", values[CoreGhostModeRepository.LEGACY_GHOST])
        client.ghostMode = false
        CoreGhostModeRepository(client, scope, plain)
        assertFalse(client.ghostMode)
    }

    @Test
    fun `core presence maps to ours`() {
        assertEquals(
            PeerPresence(isOnline = true, lastSeenMs = 1_700_000_000_000L, presence = PresenceStatus.ONLINE),
            CoreGhostModeRepository.presenceOf(PresenceInfo(seen = 1_700_000_000L, status = 1)),
        )
        val offline = CoreGhostModeRepository.presenceOf(PresenceInfo(seen = 1_700_000_000L, status = 0))
        assertFalse(offline.isOnline)
        assertEquals(1_700_000_000_000L, offline.lastSeenMs)
        val empty = CoreGhostModeRepository.presenceOf(PresenceInfo(seen = null, status = null))
        assertFalse(empty.isOnline)
        assertEquals(0L, empty.lastSeenMs)
        assertEquals(PresenceStatus.of(PresenceInfo(null, null)), empty.presence)
    }

    @Test
    fun `own presence is not asked before login`() = runTest {
        assertNull(CoreGhostModeRepository(client(), scope).checkOwnPresence())
    }

    @Test
    fun `own presence switch is on by default and kept apart from the core flags`() {
        val store = MapStore()
        val settings = OwnPresenceSettings(store)
        assertTrue(settings.shown.value)
        settings.setShown(false)
        assertEquals("false", store.values[OwnPresenceSettings.KEY_SHOWN])
        assertFalse(OwnPresenceSettings(store).shown.value)
        assertFalse(CoreGhostModeRepository(client(), scope, store).ghostMode.value)
        settings.setShown(true)
        assertTrue(OwnPresenceSettings(store).shown.value)
    }
}
