package app.maxly.platform

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Каталог данных после переименования: настройки и вход из `~/.orbitle` остаются у `~/.maxly`. */
class DataDirMigrationTest {
    private val root: File = Files.createTempDirectory("maxly-paths").toFile()
    private val legacy = File(root, ".orbitle")
    private val target = File(root, ".maxly")

    @After
    fun cleanUp() {
        root.deleteRecursively()
    }

    private fun legacyWithData() {
        File(legacy, "cache/images").mkdirs()
        File(legacy, "preferences.properties").writeText("lastUserId=42\n")
        File(legacy, "cache/images/a.bin").writeBytes(byteArrayOf(1, 2, 3))
    }

    @Test
    fun oldDirectoryIsMovedOnFirstStart() {
        legacyWithData()

        val result = DataDirMigration.resolve(target, legacy)

        assertEquals(DataDirMigration.Outcome.MOVED, result.outcome)
        assertEquals(target, result.dir)
        assertEquals("lastUserId=42\n", File(target, "preferences.properties").readText())
        assertTrue(File(target, "cache/images/a.bin").readBytes().contentEquals(byteArrayOf(1, 2, 3)))
        assertFalse(legacy.exists())
    }

    @Test
    fun existingNewDirectoryIsKeptAndOldIsLeftAlone() {
        legacyWithData()
        target.mkdirs()
        File(target, "preferences.properties").writeText("lastUserId=7\n")

        val result = DataDirMigration.resolve(target, legacy)

        assertEquals(DataDirMigration.Outcome.NOTHING_TO_DO, result.outcome)
        assertEquals(target, result.dir)
        assertEquals("lastUserId=7\n", File(target, "preferences.properties").readText())
        assertTrue(File(legacy, "preferences.properties").isFile)
    }

    @Test
    fun freshInstallUsesNewDirectory() {
        val result = DataDirMigration.resolve(target, legacy)

        assertEquals(DataDirMigration.Outcome.NOTHING_TO_DO, result.outcome)
        assertEquals(target, result.dir)
        assertFalse(legacy.exists())
    }

    @Test
    fun oldPathThatIsNotDirectoryIsIgnored() {
        legacy.writeText("not a directory")

        val result = DataDirMigration.resolve(target, legacy)

        assertEquals(DataDirMigration.Outcome.NOTHING_TO_DO, result.outcome)
        assertEquals(target, result.dir)
        assertTrue(legacy.isFile)
    }

    @Test
    fun copyFallbackWhenRenameIsRefused() {
        legacyWithData()

        val result = DataDirMigration.resolve(target, legacy) { _, _ -> throw java.io.IOException("busy") }

        assertEquals(DataDirMigration.Outcome.COPIED, result.outcome)
        assertEquals(target, result.dir)
        assertEquals("lastUserId=42\n", File(target, "preferences.properties").readText())
        assertTrue(File(target, "cache/images/a.bin").readBytes().contentEquals(byteArrayOf(1, 2, 3)))
        // Копия: старый каталог не трогается, временного не остаётся.
        assertTrue(File(legacy, "preferences.properties").isFile)
        assertFalse(File(root, ".maxly.migrating").exists())
    }

    @Test
    fun oldDirectoryStaysInUseWhenMigrationFails() {
        legacyWithData()
        // Место нового каталога внутри файла: ни переименовать, ни скопировать нельзя.
        val blocker = File(root, "blocked").apply { writeText("file") }
        val unreachable = File(blocker, ".maxly")

        val result = DataDirMigration.resolve(unreachable, legacy)

        assertEquals(DataDirMigration.Outcome.FAILED, result.outcome)
        assertEquals(legacy, result.dir)
        assertEquals("lastUserId=42\n", File(legacy, "preferences.properties").readText())
        assertFalse(File(blocker, ".maxly.migrating").exists())
    }
}
