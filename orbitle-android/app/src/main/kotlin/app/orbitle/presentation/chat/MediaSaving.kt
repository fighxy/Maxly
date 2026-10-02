package app.orbitle.presentation.chat

import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.Message
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Куда сохранить вложения сообщения: фото и видео — в галерею, файлы и голосовые — в «Загрузки». */
enum class SaveTarget { GALLERY, DOWNLOADS }

/** Что за файл сохраняется: от этого зависит папка. */
enum class SavedKind { IMAGE, VIDEO, OTHER }

/** Общие папки телефона. */
interface MediaSaver {
    /** Копирует скачанный файл [path] под именем [name] в галерею или «Загрузки». */
    suspend fun save(path: String, name: String, kind: SavedKind)
}

/** Имена сохраняемых файлов и их тип по первым байтам. */
object SaveNaming {
    private val format = DateTimeFormatter.ofPattern("yyyy-MM-dd HH.mm.ss", Locale.US)

    /** «Orbitle 2026-10-01 14.05.33.jpg», со второго вложения — « 2», « 3»… */
    fun name(timeMs: Long, index: Int, ext: String, zone: ZoneId = ZoneId.systemDefault()): String {
        val stamp = format.format(Instant.ofEpochMilli(timeMs).atZone(zone))
        val suffix = if (index > 0) " ${index + 1}" else ""
        return "Orbitle $stamp$suffix.$ext"
    }

    /** Расширение картинки по сигнатуре; неизвестное — jpg. */
    fun imageExtension(header: ByteArray): String = when {
        header.size >= 8 && header[0] == 0x89.toByte() && header[1] == 'P'.code.toByte() && header[2] == 'N'.code.toByte() -> "png"
        header.size >= 4 && header[0] == 'G'.code.toByte() && header[1] == 'I'.code.toByte() && header[2] == 'F'.code.toByte() -> "gif"
        header.size >= 12 && String(header, 0, 4, Charsets.US_ASCII) == "RIFF" && String(header, 8, 4, Charsets.US_ASCII) == "WEBP" -> "webp"
        header.size >= 12 && String(header, 4, 4, Charsets.US_ASCII) == "ftyp" && String(header, 8, 4, Charsets.US_ASCII).startsWith("hei") -> "heic"
        else -> "jpg"
    }

    /** Вложения сообщения для [target]. */
    fun attachments(message: Message, target: SaveTarget): List<ChatAttachment> = message.content.attachments.filter {
        when (target) {
            SaveTarget.GALLERY -> it is ChatAttachment.Photo || it is ChatAttachment.Video
            SaveTarget.DOWNLOADS -> it is ChatAttachment.File || it is ChatAttachment.Voice
        }
    }
}
