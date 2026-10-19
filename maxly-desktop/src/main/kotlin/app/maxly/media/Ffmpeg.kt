package app.maxly.media

import app.maxly.data.diagnostics.DiagnosticEvent
import app.maxly.platform.AppPaths
import java.io.File
import java.util.concurrent.TimeUnit

/** ОС, под которую выбирается имя файла ffmpeg. */
internal enum class HostOs {
    WINDOWS, MACOS, LINUX;

    companion object {
        val current: HostOs = System.getProperty("os.name").orEmpty().lowercase().let { name ->
            when {
                "win" in name -> WINDOWS
                "mac" in name || "darwin" in name -> MACOS
                else -> LINUX
            }
        }
    }
}

/**
 * Какой `ffmpeg` запускать. Сначала свой, из установщика: сборка под LGPL лежит в ресурсах
 * приложения (`compose.application.resources.dir`), см. `scripts/build-ffmpeg.sh`. Если его нет
 * (запуск из IDE без собранного ffmpeg) — `ffmpeg` из PATH. Свойство `maxly.ffmpeg` или
 * переменная `MAXLY_FFMPEG` задают путь явно (тесты, отладка).
 */
object Ffmpeg {
    enum class Origin { OVERRIDE, BUNDLED, PATH }

    data class Binary(val path: String, val origin: Origin)

    /** Найденный ffmpeg; `null` — его нет нигде, видео и голосовые не играют. */
    val binary: Binary? by lazy {
        resolve(
            override = System.getProperty("maxly.ffmpeg")?.takeIf { it.isNotBlank() } ?: System.getenv("MAXLY_FFMPEG")?.takeIf { it.isNotBlank() },
            resourcesDir = System.getProperty("compose.application.resources.dir")?.takeIf { it.isNotBlank() },
            os = HostOs.current,
            prepare = ::executable,
            works = ::works,
        ).also { found ->
            // В журнал — откуда ffmpeg, без пути (в нём имя пользователя).
            DiagnosticEvent.event("media.ffmpeg", mapOf("origin" to (found?.origin?.name ?: "NONE")), snapshot = true)
        }
    }

    /** Путь для [ProcessBuilder]: без найденного ffmpeg — просто `ffmpeg`, запуск упадёт как раньше. */
    val path: String get() = binary?.path ?: "ffmpeg"

    /** Команда ffmpeg с аргументами [args]. */
    fun command(vararg args: String): List<String> = listOf(path) + args

    fun command(args: List<String>): List<String> = listOf(path) + args

    internal fun fileName(os: HostOs): String = if (os == HostOs.WINDOWS) "ffmpeg.exe" else "ffmpeg"

    /**
     * Порядок поиска: явный путь, ffmpeg из ресурсов приложения, PATH. [prepare] делает файл
     * исполняемым (или отдаёт исполняемую копию), [works] проверяет запуском `-version`.
     */
    internal fun resolve(
        override: String?,
        resourcesDir: String?,
        os: HostOs,
        prepare: (File) -> File?,
        works: (String) -> Boolean,
    ): Binary? {
        override?.let(::File)?.takeIf { it.isFile }?.let(prepare)?.let { file ->
            if (works(file.absolutePath)) return Binary(file.absolutePath, Origin.OVERRIDE)
        }
        resourcesDir?.let { File(it, fileName(os)) }?.takeIf { it.isFile }?.let(prepare)?.let { file ->
            if (works(file.absolutePath)) return Binary(file.absolutePath, Origin.BUNDLED)
        }
        return if (works("ffmpeg")) Binary("ffmpeg", Origin.PATH) else null
    }

    /**
     * Исполняемый файл ffmpeg. Если установщик потерял бит исполнения, а папка только для
     * чтения (`/opt` у .deb), ffmpeg копируется в кэш и запускается оттуда.
     */
    private fun executable(file: File): File? {
        if (HostOs.current == HostOs.WINDOWS || file.canExecute()) return file
        if (runCatching { file.setExecutable(true) }.getOrDefault(false) && file.canExecute()) return file
        return runCatching {
            val copy = File(AppPaths.cacheDir, "bin/${file.name}")
            if (copy.length() != file.length()) {
                copy.parentFile.mkdirs()
                file.copyTo(copy, overwrite = true)
            }
            copy.setExecutable(true)
            copy.takeIf { it.canExecute() }
        }.getOrNull()
    }

    private fun works(path: String): Boolean = runCatching {
        val process = ProcessBuilder(path, "-hide_banner", "-version").redirectErrorStream(true).start()
        process.inputStream.readBytes()
        process.waitFor(10, TimeUnit.SECONDS) && process.exitValue() == 0
    }.getOrDefault(false)
}
