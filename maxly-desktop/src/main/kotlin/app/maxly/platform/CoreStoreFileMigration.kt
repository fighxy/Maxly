package app.maxly.platform

import app.maxly.data.CoreStoreMigration
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermissions
import java.util.Properties

/**
 * Вход и сессия ядра после переименования: ядро на ПК хранит их в
 * `<max.kmp.dir или ~/.max-kmp>/<namespace>.properties` под ключами `max.<namespace>.*`.
 * Пространство имён сменилось с `orbitle-desktop` на `maxly-desktop`, поэтому при первом
 * запуске старый файл переписывается в новый с новыми ключами, иначе пришлось бы входить заново.
 *
 * Ничего не делает, если новый файл уже есть или старого нет. Новый файл появляется целиком
 * (временный файл с правами только владельца и атомарная замена), старый удаляется лишь после
 * этого, чтобы токен не лежал в двух местах. При ошибке старый файл остаётся, и перенос
 * повторится при следующем запуске.
 */
object CoreStoreFileMigration {
    enum class Outcome { NOTHING_TO_DO, MOVED, FAILED }

    class Result(val outcome: Outcome, val error: Throwable? = null)

    /** Каталог хранилища ядра на JVM, как в `PlatformSession.jvm.kt` ядра. */
    fun coreDir(): File =
        System.getProperty("max.kmp.dir")?.let(::File) ?: File(System.getProperty("user.home"), ".max-kmp")

    fun migrate(dir: File, legacyNamespace: String, namespace: String): Result {
        val legacy = File(dir, "$legacyNamespace.properties")
        val target = File(dir, "$namespace.properties")
        if (target.exists() || !legacy.isFile) return Result(Outcome.NOTHING_TO_DO)
        val tmp = File(dir, "$namespace.properties.migrating")
        return try {
            val old = Properties().also { p -> legacy.inputStream().use(p::load) }
            val entries = old.stringPropertyNames().associateWith { old.getProperty(it) }
            val moved = Properties().apply { putAll(CoreStoreMigration.rekey(entries, legacyNamespace, namespace)) }
            Files.deleteIfExists(tmp.toPath())
            if (posix(dir)) {
                Files.createFile(tmp.toPath(), PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")))
            }
            tmp.outputStream().use { moved.store(it, "max-kmp credentials") }
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
            Files.deleteIfExists(legacy.toPath())
            Result(Outcome.MOVED)
        } catch (e: Exception) {
            runCatching { Files.deleteIfExists(tmp.toPath()) }
            Result(Outcome.FAILED, e)
        }
    }

    private fun posix(dir: File): Boolean = dir.toPath().fileSystem.supportedFileAttributeViews().contains("posix")
}
