package app.maxly.data

import org.junit.Test
import org.junit.Assert.assertEquals

class CoreStoreMigrationTest {
    @Test
    fun movesCoreKeysToTheNewNamespace() {
        val legacy = mapOf(
            "max.orbitle-desktop.token" to "t",
            "max.orbitle-desktop.deviceId" to "d",
            "max.orbitle-desktop.localReads.5" to "1",
            "max.orbitle-desktopX.token" to "other",
            "unrelated" to "u",
        )
        assertEquals(
            mapOf(
                "max.maxly-desktop.token" to "t",
                "max.maxly-desktop.deviceId" to "d",
                "max.maxly-desktop.localReads.5" to "1",
                "max.orbitle-desktopX.token" to "other",
                "unrelated" to "u",
            ),
            CoreStoreMigration.rekey(legacy, "orbitle-desktop", "maxly-desktop"),
        )
    }
}
