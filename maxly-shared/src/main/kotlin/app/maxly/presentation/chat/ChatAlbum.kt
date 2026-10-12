package app.maxly.presentation.chat

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Плитка альбома: место кадра [index] внутри альбома, в dp. */
data class AlbumTile(val index: Int, val x: Double, val y: Double, val width: Double, val height: Double)

/** Раскладка альбома: размер и плитки. */
data class AlbumLayout(val width: Double, val height: Double, val tiles: List<AlbumTile>)

/**
 * Альбом рядами по пропорциям кадров — как на iOS (`ChatContentFormat.album`).
 *
 * Один–три кадра — привычные ряды (узкий первый из трёх — слева, два других — колонкой справа).
 * С четырёх кадров перебираются все разбиения на ряды по 1–4 кадра: лучшее — с рядами высотой
 * ближе к 0,4 ширины, без рядов ниже 0,22 ширины и в пределах высоты; при равенстве ряд сверху
 * не больше нижнего. Шесть широких сканов ложатся по два в ряд, а не по три полосками.
 * Не влезающий по высоте альбом уменьшается целиком; с семи кадров он может быть выше.
 */
object ChatAlbum {
    fun layout(aspects: List<Double>, maxWidth: Double, maxHeight: Double = 360.0, gap: Double = 2.0): AlbumLayout {
        val width = max(1.0, maxWidth)
        val space = max(0.0, gap)
        val ratios = aspects.map(::clamped)
        if (ratios.isEmpty()) return AlbumLayout(0.0, 0.0, emptyList())
        val limit = max(1.0, if (ratios.size >= 7) maxHeight * 1.35 else maxHeight)
        val placed = when {
            ratios.size == 3 && ratios[0] < 1.15 -> portraitTrio(ratios, width, space)
            ratios.size >= 4 -> pack(balancedRows(ratios, width, space, limit), ratios, width, space)
            else -> pack(rowCounts(ratios), ratios, width, space)
        }
        return finish(placed, width, limit)
    }

    /** Лучшее разбиение на ряды для альбома из четырёх и больше кадров. */
    fun balancedRows(aspects: List<Double>, width: Double, gap: Double, maxHeight: Double): List<Int> {
        val ideal = width * 0.4
        val lowest = width * 0.22
        var bestScore = Double.POSITIVE_INFINITY
        var bestRows = listOf(aspects.size)
        fun score(rows: List<Int>): Double {
            var cursor = 0
            var total = gap * (rows.size - 1)
            var result = 0.0
            rows.forEachIndexed { index, count ->
                val height = measure(aspects.subList(cursor, cursor + count), width, gap).first
                cursor += count
                total += height
                result += ((height - ideal) / ideal).pow(2)
                if (height < lowest) result += 3
                if (index > 0 && rows[index - 1] > count) result += 0.05
            }
            if (total > maxHeight) {
                val over = (total - maxHeight) / maxHeight
                result += over * over * 20 + over * 2
            }
            return result
        }
        fun walk(rows: List<Int>, left: Int) {
            if (left == 0) {
                val value = score(rows)
                if (value < bestScore) {
                    bestScore = value
                    bestRows = rows
                }
                return
            }
            for (count in 1..min(4, left)) walk(rows + count, left - count)
        }
        walk(emptyList(), aspects.size)
        return bestRows
    }

    private fun clamped(value: Double): Double {
        val ratio = if (value.isFinite() && value > 0) value else 1.0
        return ratio.coerceIn(0.45, 2.2)
    }

    private fun rowCounts(aspects: List<Double>): List<Int> = when (aspects.size) {
        1 -> listOf(1)
        2 -> if (aspects.all { it >= 1.15 }) listOf(1, 1) else listOf(2)
        else -> listOf(1, 2)
    }

    private fun pack(counts: List<Int>, aspects: List<Double>, width: Double, gap: Double): List<AlbumTile> {
        val tiles = ArrayList<AlbumTile>()
        var cursor = 0
        var y = 0.0
        for (count in counts) {
            val (height, widths) = measure(aspects.subList(cursor, cursor + count), width, gap)
            var x = 0.0
            widths.forEachIndexed { offset, tileWidth ->
                tiles += AlbumTile(cursor + offset, x, y, tileWidth, height)
                x += tileWidth + gap
            }
            y += height + if (cursor + count < aspects.size) gap else 0.0
            cursor += count
        }
        return tiles
    }

    private fun measure(aspects: List<Double>, width: Double, gap: Double): Pair<Double, List<Double>> {
        if (aspects.size <= 1) return (width / (aspects.firstOrNull() ?: 1.0)) to listOf(width)
        val available = max(1.0, width - gap * (aspects.size - 1))
        val height = available / aspects.sum()
        return height to aspects.map { height * it }
    }

    private fun portraitTrio(aspects: List<Double>, width: Double, gap: Double): List<AlbumTile> {
        val leftWidth = (width - gap) * 0.64
        val rightWidth = width - gap - leftWidth
        val top = rightWidth / aspects[1]
        val bottom = rightWidth / aspects[2]
        return listOf(
            AlbumTile(0, 0.0, 0.0, leftWidth, top + gap + bottom),
            AlbumTile(1, leftWidth + gap, 0.0, rightWidth, top),
            AlbumTile(2, leftWidth + gap, top + gap, rightWidth, bottom),
        )
    }

    private fun finish(placed: List<AlbumTile>, width: Double, maxHeight: Double): AlbumLayout {
        var albumWidth = width
        var albumHeight = placed.maxOf { it.y + it.height }
        var tiles = snap(placed, albumWidth, albumHeight)
        if (albumHeight > maxHeight && albumHeight > 0) {
            val scale = maxHeight / albumHeight
            tiles = tiles.map { AlbumTile(it.index, it.x * scale, it.y * scale, it.width * scale, it.height * scale) }
            albumWidth *= scale
            albumHeight = maxHeight
            tiles = snap(tiles, albumWidth, albumHeight)
        }
        return AlbumLayout(albumWidth, albumHeight, tiles)
    }

    /** Края, почти касающиеся края альбома, дотягиваются до него: без щели в долю точки. */
    private fun snap(tiles: List<AlbumTile>, width: Double, height: Double): List<AlbumTile> = tiles.map { tile ->
        tile.copy(
            width = if (tile.x + tile.width >= width - 1) max(1.0, width - tile.x) else tile.width,
            height = if (tile.y + tile.height >= height - 1) max(1.0, height - tile.y) else tile.height,
        )
    }
}
