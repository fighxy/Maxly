package app.maxly.presentation.chat

import app.maxly.domain.ChatAttachment
import app.maxly.domain.Message
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Куда сохранить вложения сообщения: фото и видео — в галерею, файлы и голосовые — в «Загрузки». */
enum class SaveTarget { GALLERY, DOWNLOADS }

/** Что за файл сохраняется: от этого зависит папка. */
enum class SavedKind { IMAGE, VIDEO, OTHER }

/** Общие папки устройства. */
interface MediaSaver {
    /**
     * Копирует скачанный файл [path] под именем [name]: в [directory], если её выбрали, иначе в
     * общую папку для [kind]. Фото в WebP и HEIC ([SaveNaming.needsTranscode]) сохраняются в JPEG
     * (прозрачное — на белом), если платформа умеет их прочитать.
     */
    suspend fun save(path: String, name: String, kind: SavedKind, directory: String? = null)

    /** Куда попадает [kind] без выбранной папки: для «Сохранено в …». */
    fun place(kind: SavedKind): String = if (kind == SavedKind.OTHER) "«Загрузки»" else "галерею"
}

/** Имена сохраняемых файлов и их тип по первым байтам. */
object SaveNaming {
    private val format = DateTimeFormatter.ofPattern("yyyy-MM-dd HH.mm.ss", Locale.US)

    /** «Maxly 2026-10-01 14.05.33.jpg», со второго вложения — « 2», « 3»… */
    fun name(timeMs: Long, index: Int, ext: String, zone: ZoneId = ZoneId.systemDefault()): String {
        val stamp = format.format(Instant.ofEpochMilli(timeMs).atZone(zone))
        val suffix = if (index > 0) " ${index + 1}" else ""
        return "Maxly $stamp$suffix.$ext"
    }

    /** Расширение картинки по сигнатуре; неизвестное — jpg. */
    fun imageExtension(header: ByteArray): String = when {
        header.size >= 8 && header[0] == 0x89.toByte() && header[1] == 'P'.code.toByte() && header[2] == 'N'.code.toByte() -> "png"
        header.size >= 4 && header[0] == 'G'.code.toByte() && header[1] == 'I'.code.toByte() && header[2] == 'F'.code.toByte() -> "gif"
        header.size >= 12 && String(header, 0, 4, Charsets.US_ASCII) == "RIFF" && String(header, 8, 4, Charsets.US_ASCII) == "WEBP" -> "webp"
        header.size >= 12 && String(header, 4, 4, Charsets.US_ASCII) == "ftyp" && String(header, 8, 4, Charsets.US_ASCII).startsWith("hei") -> "heic"
        else -> "jpg"
    }

    /** WebP и HEIC открывает не каждая программа: такие фото сохраняются перекодированными. */
    fun needsTranscode(name: String): Boolean = name.substringAfterLast('.', "").lowercase() in setOf("webp", "heic", "heif")

    /** То же имя с расширением [ext]. */
    fun withExtension(name: String, ext: String): String {
        val dot = name.lastIndexOf('.')
        return (if (dot > 0) name.substring(0, dot) else name) + ".$ext"
    }

    /** Имя без запрещённых в путях символов. */
    fun safe(name: String): String = name.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_").trim().ifEmpty { "Maxly" }

    /** Свободное имя в папке: «x.jpg», затем «x 2.jpg», «x 3.jpg»… */
    fun freeName(name: String, taken: (String) -> Boolean): String {
        if (!taken(name)) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var index = 2
        while (taken("$base $index$ext")) index += 1
        return "$base $index$ext"
    }

    /** Вложения сообщения для [target]. */
    fun attachments(message: Message, target: SaveTarget): List<ChatAttachment> = message.content.attachments.filter {
        when (target) {
            SaveTarget.GALLERY -> it is ChatAttachment.Photo || it is ChatAttachment.Video
            SaveTarget.DOWNLOADS -> it is ChatAttachment.File || it is ChatAttachment.Voice
        }
    }
}
