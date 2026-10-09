package app.maxly.platform

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Перенос каталога данных после переименования приложения: `~/.orbitle` → `~/.maxly`.
 * В каталоге настройки (последний вошедший пользователь, вид, окно), кэш, журналы и хранилище
 * мини-приложений, поэтому без переноса клиент после обновления выглядел бы как новая установка.
 *
 * Переносится только при первом запуске: нового каталога ещё нет, а старый есть. Сначала
 * каталог переименовывается целиком; если ОС не даёт (другой диск, файл занят), он копируется
 * во временный каталог рядом и тот переименовывается в новый, а старый остаётся на месте.
 * Если не вышло и это, приложение работает со старым каталогом и попробует снова при
 * следующем запуске.
 */
object DataDirMigration {
    enum class Outcome { NOTHING_TO_DO, MOVED, COPIED, FAILED }

    class Result(val dir: File, val outcome: Outcome, val error: Throwable? = null)

    /** [rename] — атомарное переименование; в тестах подменяется, чтобы проверить запасной путь. */
    fun resolve(target: File, legacy: File, rename: (File, File) -> Unit = ::atomicMove): Result {
        if (target.exists() || !legacy.isDirectory) return Result(target, Outcome.NOTHING_TO_DO)
        target.absoluteFile.parentFile?.mkdirs()
        try {
            rename(legacy, target)
            return Result(target, Outcome.MOVED)
        } catch (_: Exception) {
            // Переименовать нельзя: копия ниже.
        }
        val partial = File(target.absoluteFile.parentFile, target.name + ".migrating")
        return try {
            partial.deleteRecursively()
            if (!legacy.copyRecursively(partial, overwrite = true)) throw IOException("Не удалось скопировать $legacy")
            atomicMove(partial, target)
            Result(target, Outcome.COPIED)
        } catch (e: Exception) {
            partial.deleteRecursively()
            Result(legacy, Outcome.FAILED, e)
        }
    }

    private fun atomicMove(from: File, to: File) {
        Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE)
    }
}
