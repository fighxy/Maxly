package app.maxly.media

import app.maxly.data.diagnostics.DiagnosticEvent
import app.maxly.platform.AppPaths
import java.io.File
import java.util.concurrent.TimeUnit

/** ОС, под которую выбираются имя файла ffmpeg и кодировщик H.264. */
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

/**
 * Кодировщик H.264 для кружка. В установщике свой ffmpeg без libx264 и libopenh264, поэтому
 * сжимает система: Media Foundation на Windows, VideoToolbox на macOS, VA-API на Linux.
 * [global] — ключи до входа (устройство VA-API), [codec] — после.
 */
internal data class H264Encoder(val name: String, val global: List<String> = emptyList(), val codec: List<String>)

internal object H264Encoders {
    const val BITRATE = "1200k"

    /** Кандидаты по порядку. libopenh264 и libx264 бывают только у ffmpeg из PATH, в наш не входят. */
    fun candidates(os: HostOs, renderNodes: List<String> = vaapiNodes()): List<H264Encoder> {
        val system = when (os) {
            HostOs.WINDOWS -> listOf(H264Encoder("h264_mf", codec = listOf("-c:v", "h264_mf", "-b:v", BITRATE, "-pix_fmt", "nv12")))
            HostOs.MACOS -> listOf(H264Encoder("h264_videotoolbox", codec = listOf("-c:v", "h264_videotoolbox", "-allow_sw", "1", "-b:v", BITRATE, "-pix_fmt", "yuv420p")))
            HostOs.LINUX -> renderNodes.map { node ->
                H264Encoder(
                    "h264_vaapi",
                    global = listOf("-vaapi_device", node),
                    codec = listOf("-vf", "format=nv12,hwupload", "-c:v", "h264_vaapi", "-b:v", BITRATE),
                )
            }
        }
        return system + listOf(
            H264Encoder("libopenh264", codec = listOf("-c:v", "libopenh264", "-b:v", BITRATE, "-pix_fmt", "yuv420p")),
            H264Encoder("libx264", codec = listOf("-c:v", "libx264", "-preset", "veryfast", "-crf", "26", "-pix_fmt", "yuv420p")),
        )
    }

    /** Узлы видеокарты для VA-API: `/dev/dri/renderD128` и дальше. */
    fun vaapiNodes(): List<String> =
        File("/dev/dri").listFiles { file -> file.name.startsWith("renderD") }.orEmpty().map { it.absolutePath }.sorted()

    /** Сжатие сырого YUV 4:2:0 [side]×[side] из `pipe:0` в [output]. */
    fun encodeCommand(ffmpeg: String, encoder: H264Encoder, side: Int, fps: Int, output: String): List<String> =
        listOf(ffmpeg, "-y", "-hide_banner", "-loglevel", "error") + encoder.global +
            listOf("-f", "rawvideo", "-pix_fmt", "yuv420p", "-s", "${side}x$side", "-r", "$fps", "-i", "pipe:0") +
            encoder.codec + output

    /** Первый кандидат, который [works]; `null` — сжимать нечем. */
    fun pick(candidates: List<H264Encoder>, works: (H264Encoder) -> Boolean): H264Encoder? = candidates.firstOrNull(works)

    /**
     * Пробное сжатие пары кадров: кодировщик есть в сборке и система его дала (на Windows N
     * без Media Feature Pack h264_mf не откроется, без драйвера VA-API — h264_vaapi).
     */
    fun probe(ffmpeg: String, encoder: H264Encoder, side: Int = 64, fps: Int = 25): Boolean = runCatching {
        val command = encodeCommand(ffmpeg, encoder, side, fps, "-").toMutableList()
        command.add(command.size - 1, "-f")
        command.add(command.size - 1, "null")
        val process = ProcessBuilder(command).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        val drain = Thread { runCatching { process.inputStream.readBytes() } }.apply { isDaemon = true; start() }
        val frame = ByteArray(side * side * 3 / 2).also { bytes ->
            bytes.fill(16, 0, side * side)
            bytes.fill(-128, side * side, bytes.size)
        }
        runCatching { process.outputStream.use { out -> repeat(10) { out.write(frame) } } }
        val done = process.waitFor(15, TimeUnit.SECONDS)
        if (!done) process.destroyForcibly()
        drain.join(1_000)
        done && process.exitValue() == 0
    }.getOrDefault(false)

    @Volatile private var chosen: Pair<String, H264Encoder?>? = null

    /** Кодировщик для этого ffmpeg; проверка — один раз за запуск. */
    @Synchronized
    fun forCurrent(): H264Encoder? {
        val ffmpeg = Ffmpeg.binary?.path ?: return null
        chosen?.takeIf { it.first == ffmpeg }?.let { return it.second }
        val encoder = pick(candidates(HostOs.current)) { probe(ffmpeg, it) }
        DiagnosticEvent.event("media.h264_encoder", mapOf("encoder" to (encoder?.name ?: "NONE")), snapshot = true)
        chosen = ffmpeg to encoder
        return encoder
    }

    /** Почему кружок не пишется, для подсказки под полем ввода. */
    fun unavailableText(os: HostOs, ffmpegFound: Boolean): String = when {
        !ffmpegFound -> "Кружки не записываются: не найден ffmpeg"
        os == HostOs.WINDOWS -> "Кружки не записываются: в Windows нет кодировщика H.264 (Media Foundation). В выпусках N и KN установите Media Feature Pack"
        os == HostOs.MACOS -> "Кружки не записываются: macOS не дала кодировщик H.264 (VideoToolbox)"
        else -> "Кружки не записываются: нет кодировщика H.264 через VA-API. Нужен драйвер VA-API видеокарты"
    }
}
