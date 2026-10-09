package app.maxly.presentation.photo

import java.io.DataInputStream
import java.io.InputStream

/** Маленький ограниченный JPEG APP1 reader, без зависимости платформы. */
object PhotoExif {
    fun orientation(input: InputStream): Int = runCatching {
        val data = DataInputStream(input)
        if (data.readUnsignedShort() != 0xffd8) return 1
        var scanned = 2
        while (scanned < 1024 * 1024) {
            if (data.readUnsignedByte() != 0xff) return 1
            var marker = data.readUnsignedByte()
            while (marker == 0xff) marker = data.readUnsignedByte()
            if (marker == 0xda || marker == 0xd9) return 1
            if (marker == 0x01 || marker in 0xd0..0xd7) continue
            val length = data.readUnsignedShort() - 2
            if (length < 0) return 1
            val segment = ByteArray(length)
            data.readFully(segment)
            scanned += length + 4
            if (marker != 0xe1 || segment.size < 14 || !segment.copyOfRange(0, 6).contentEquals(byteArrayOf(69, 120, 105, 102, 0, 0))) continue
            val little = segment[6] == 73.toByte() && segment[7] == 73.toByte()
            if (!little && !(segment[6] == 77.toByte() && segment[7] == 77.toByte())) continue
            fun number(offset: Int, count: Int): Int {
                require(offset >= 0 && offset + count <= segment.size)
                var value = 0
                for (i in 0 until count) value = value or ((segment[offset + i].toInt() and 255) shl ((if (little) i else count - i - 1) * 8))
                return value
            }
            if (number(8, 2) != 42) continue
            val directory = 6 + number(10, 4)
            val count = number(directory, 2)
            require(count <= (segment.size - directory - 2) / 12)
            for (i in 0 until count) {
                val offset = directory + 2 + i * 12
                if (number(offset, 2) == 0x112 && number(offset + 2, 2) == 3 && number(offset + 4, 4) == 1) {
                    return number(offset + 8, 2).takeIf { it in 1..8 } ?: 1
                }
            }
        }
        1
    }.getOrDefault(1)

    fun position(orientation: Int, x: Int, y: Int, width: Int, height: Int): Pair<Int, Int> = when (orientation) {
        2 -> width - 1 - x to y
        3 -> width - 1 - x to height - 1 - y
        4 -> x to height - 1 - y
        5 -> y to x
        6 -> height - 1 - y to x
        7 -> height - 1 - y to width - 1 - x
        8 -> y to width - 1 - x
        else -> x to y
    }
}
