package app.maxly.platform

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.util.Properties

/** Вход ядра из пространства `orbitle-desktop` переезжает в `maxly-desktop`. */
class CoreStoreFileMigrationTest {
    private val dir: File = Files.createTempDirectory("maxly-core-store").toFile()
    private val legacy = File(dir, "orbitle-desktop.properties")
    private val target = File(dir, "maxly-desktop.properties")

    @After
    fun cleanUp() {
        dir.deleteRecursively()
    }

    private fun write(file: File, vararg entries: Pair<String, String>) {
        val p = Properties().apply { entries.forEach { (k, v) -> setProperty(k, v) } }
        file.outputStream().use { p.store(it, null) }
    }

    private fun read(file: File): Properties = Properties().also { p -> file.inputStream().use(p::load) }

    @Test
    fun loginMovesToTheNewNamespace() {
        write(legacy, "max.orbitle-desktop.token" to "секрет=:#", "max.orbitle-desktop.userId" to "42", "max.orbitle-desktop.ghostMode" to "true")

        val result = CoreStoreFileMigration.migrate(dir, "orbitle-desktop", "maxly-desktop")

        assertEquals(CoreStoreFileMigration.Outcome.MOVED, result.outcome)
        assertFalse(legacy.exists())
        val moved = read(target)
        assertEquals("секрет=:#", moved.getProperty("max.maxly-desktop.token"))
        assertEquals("42", moved.getProperty("max.maxly-desktop.userId"))
        assertEquals("true", moved.getProperty("max.maxly-desktop.ghostMode"))
        assertNull(moved.getProperty("max.orbitle-desktop.token"))
        assertFalse(File(dir, "maxly-desktop.properties.migrating").exists())
        if (dir.toPath().fileSystem.supportedFileAttributeViews().contains("posix")) {
            assertEquals(PosixFilePermissions.fromString("rw-------"), Files.getPosixFilePermissions(target.toPath()))
        }
    }

    @Test
    fun existingNewStoreIsNotOverwritten() {
        write(legacy, "max.orbitle-desktop.token" to "old")
        write(target, "max.maxly-desktop.token" to "new")

        val result = CoreStoreFileMigration.migrate(dir, "orbitle-desktop", "maxly-desktop")

        assertEquals(CoreStoreFileMigration.Outcome.NOTHING_TO_DO, result.outcome)
        assertEquals("new", read(target).getProperty("max.maxly-desktop.token"))
        assertTrue(legacy.exists())
    }

    @Test
    fun nothingToMoveWithoutOldStore() {
        assertEquals(CoreStoreFileMigration.Outcome.NOTHING_TO_DO, CoreStoreFileMigration.migrate(dir, "orbitle-desktop", "maxly-desktop").outcome)
        assertFalse(target.exists())
    }

    @Test
    fun failureKeepsTheOldStore() {
        write(legacy, "max.orbitle-desktop.token" to "t")
        // Каталог на месте временного файла: запись падает до замены.
        File(dir, "maxly-desktop.properties.migrating/x").apply { parentFile.mkdirs(); writeText("x") }

        val result = CoreStoreFileMigration.migrate(dir, "orbitle-desktop", "maxly-desktop")

        assertEquals(CoreStoreFileMigration.Outcome.FAILED, result.outcome)
        assertTrue(legacy.exists())
        assertFalse(target.exists())
    }
}
