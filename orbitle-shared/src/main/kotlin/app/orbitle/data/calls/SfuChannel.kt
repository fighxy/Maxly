package app.orbitle.data.calls

import java.io.ByteArrayOutputStream

/**
 * Служебные каналы данных SFU: `producerCommand` (наши команды) и `producerNotification`
 * (алиасы дорожек, слоты видео и уровни звука). Сервер говорит в них MessagePack; схема
 * кадров — как у Komet (`sfu_data_channel.dart`), кодек свой.
 */
object SfuChannel {
    const val COMMAND_LABEL = "producerCommand"
    const val NOTIFICATION_LABEL = "producerNotification"

    /** Одно окно видео в раскладке: чьё видео и какого размера нужно. */
    data class LayoutItem(val trackKey: String, val width: Int = 640, val height: Int = 360)

    /** Уведомление канала `producerNotification`. */
    sealed interface Notification {
        /** Ключи дорожек получили короткие номера (алиасы). */
        data class Aliases(val map: Map<Int, String>) : Notification

        /** Ключ дорожки → номер видеослота (`video-pat-<слот>`). */
        data class Slots(val map: Map<String, Int>) : Notification

        /** Ключ дорожки → уровень звука 0…127. */
        data class Levels(val map: Map<String, Int>) : Notification
    }

    /**
     * Команда `update-display-layout` (код 0): какие видео присылать. Байты повторяют то, что
     * шлёт Komet: тип, версия, номер, `snapshot`, массив окон или `nil`, завершающий `nil`.
     */
    fun displayLayout(items: List<LayoutItem>, sequence: Int, snapshot: Boolean = true): ByteArray {
        val writer = MessagePackWriter()
        writer.int(0)
        writer.int(0)
        writer.int(sequence.toLong())
        writer.bool(snapshot)
        if (items.isEmpty()) {
            writer.nil()
        } else {
            writer.arrayHeader(items.size * 2)
            for (item in items) {
                writer.string(item.trackKey)
                writer.int(0)
                writer.nil()
                writer.int(item.width.toLong())
                writer.int(item.height.toLong())
                writer.int(0)
            }
        }
        writer.nil()
        return writer.bytes()
    }

    /** Разбирает уведомление; алиасы из прошлых кадров переводят номера в ключи. `null` — незнакомый или битый кадр. */
    fun parse(data: ByteArray, aliases: Map<Int, String>): Notification? {
        if (data.isEmpty()) return null
        val reader = MessagePackReader(data, 1)
        return try {
            when (data[0].toInt()) {
                1 -> {
                    val map = HashMap<Int, String>()
                    repeat(reader.mapHeader()) {
                        val key = reader.string()
                        map[reader.int().toInt()] = key
                    }
                    Notification.Aliases(map)
                }
                2 -> {
                    val slots = HashMap<String, Int>()
                    for (slot in 0 until reader.arrayHeader()) {
                        aliases[reader.int().toInt()]?.let { slots[it] = slot }
                    }
                    Notification.Slots(slots)
                }
                6 -> {
                    val levels = HashMap<String, Int>()
                    repeat(reader.mapHeader()) {
                        val alias = reader.int().toInt()
                        val level = reader.int().toInt()
                        aliases[alias]?.let { levels[it] = level }
                    }
                    Notification.Levels(levels)
                }
                else -> null
            }
        } catch (_: MessagePackReader.Malformed) {
            null
        }
    }
}

/** Запись MessagePack: только то, что нужно командам SFU. */
internal class MessagePackWriter {
    private val out = ByteArrayOutputStream()

    fun bytes(): ByteArray = out.toByteArray()

    fun nil() = out.write(0xC0)

    fun bool(value: Boolean) = out.write(if (value) 0xC3 else 0xC2)

    fun int(value: Long) {
        when {
            value in 0..0x7F -> out.write(value.toInt())
            value in 0x80..0xFF -> { out.write(0xCC); be(value, 1) }
            value in 0x100..0xFFFF -> { out.write(0xCD); be(value, 2) }
            value in 0x10000..0xFFFF_FFFFL -> { out.write(0xCE); be(value, 4) }
            value > 0xFFFF_FFFFL -> { out.write(0xCF); be(value, 8) }
            value >= -32 -> out.write(value.toInt() and 0xFF)
            value >= -128 -> { out.write(0xD0); be(value, 1) }
            value >= -32768 -> { out.write(0xD1); be(value, 2) }
            value >= Int.MIN_VALUE -> { out.write(0xD2); be(value, 4) }
            else -> { out.write(0xD3); be(value, 8) }
        }
    }

    fun string(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        val size = bytes.size.toLong()
        when {
            size < 32 -> out.write(0xA0 or bytes.size)
            size <= 0xFF -> { out.write(0xD9); be(size, 1) }
            size <= 0xFFFF -> { out.write(0xDA); be(size, 2) }
            else -> { out.write(0xDB); be(size, 4) }
        }
        out.write(bytes)
    }

    fun mapHeader(count: Int) = header(count, 0x80, 0xDE, 0xDF)

    fun arrayHeader(count: Int) = header(count, 0x90, 0xDC, 0xDD)

    private fun header(count: Int, fix: Int, short: Int, long: Int) {
        when {
            count < 16 -> out.write(fix or count)
            count <= 0xFFFF -> { out.write(short); be(count.toLong(), 2) }
            else -> { out.write(long); be(count.toLong(), 4) }
        }
    }

    private fun be(value: Long, bytes: Int) {
        for (shift in (bytes - 1) * 8 downTo 0 step 8) out.write(((value ushr shift) and 0xFF).toInt())
    }
}

/** Чтение MessagePack: целые, строки, заголовки массивов и словарей. */
internal class MessagePackReader(private val bytes: ByteArray, private var position: Int = 0) {
    class Malformed : Exception()

    fun int(): Long {
        val head = byte()
        return when (head) {
            in 0x00..0x7F -> head.toLong()
            in 0xE0..0xFF -> (head - 0x100).toLong()
            0xCC -> unsigned(1)
            0xCD -> unsigned(2)
            0xCE -> unsigned(4)
            0xCF -> unsigned(8)
            0xD0 -> unsigned(1).toByte().toLong()
            0xD1 -> unsigned(2).toShort().toLong()
            0xD2 -> unsigned(4).toInt().toLong()
            0xD3 -> unsigned(8)
            else -> throw Malformed()
        }
    }

    fun string(): String {
        val head = byte()
        val length = when (head) {
            in 0xA0..0xBF -> head and 0x1F
            0xD9 -> unsigned(1).toInt()
            0xDA -> unsigned(2).toInt()
            0xDB -> unsigned(4).toInt()
            else -> throw Malformed()
        }
        if (length < 0 || position + length > bytes.size) throw Malformed()
        val text = String(bytes, position, length, Charsets.UTF_8)
        position += length
        return text
    }

    fun mapHeader(): Int = when (val head = byte()) {
        in 0x80..0x8F -> head and 0x0F
        0xDE -> unsigned(2).toInt()
        0xDF -> unsigned(4).toInt()
        else -> throw Malformed()
    }

    fun arrayHeader(): Int = when (val head = byte()) {
        in 0x90..0x9F -> head and 0x0F
        0xDC -> unsigned(2).toInt()
        0xDD -> unsigned(4).toInt()
        else -> throw Malformed()
    }

    private fun byte(): Int {
        if (position >= bytes.size) throw Malformed()
        return bytes[position++].toInt() and 0xFF
    }

    private fun unsigned(count: Int): Long {
        var value = 0L
        repeat(count) { value = (value shl 8) or byte().toLong() }
        return value
    }
}
