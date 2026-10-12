package app.maxly.presentation.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatAlbumTest {
    @Test
    fun wideScansLieTwoPerRowInsteadOfThinStrips() {
        assertEquals(listOf(2, 2, 2), ChatAlbum.balancedRows(List(6) { 2.2 }, 300.0, 2.0, 360.0))
        val scans = ChatAlbum.layout(List(6) { 2.2 }, 300.0)
        assertEquals(300.0, scans.width, 0.01)
        assertTrue(scans.tiles.all { it.height >= 60 })
    }

    @Test
    fun squaresKeepTheUsualRows() {
        assertEquals(listOf(2, 2), ChatAlbum.balancedRows(List(4) { 1.0 }, 300.0, 2.0, 360.0))
        assertEquals(listOf(2, 3), ChatAlbum.balancedRows(List(5) { 1.0 }, 300.0, 2.0, 360.0))
        assertEquals(listOf(3, 3), ChatAlbum.balancedRows(List(6) { 1.0 }, 300.0, 2.0, 360.0))
    }

    @Test
    fun smallAlbumsAndTallLimit() {
        val landscape = ChatAlbum.layout(listOf(1.6), 300.0)
        assertEquals(187.5, landscape.height, 0.01)
        val portraits = ChatAlbum.layout(listOf(0.7, 0.8), 300.0)
        assertEquals(portraits.tiles[0].y, portraits.tiles[1].y, 0.01)
        val stacked = ChatAlbum.layout(listOf(1.5, 1.6), 300.0)
        assertEquals(0.0, stacked.tiles[1].x, 0.01)
        assertTrue(stacked.height <= 360.01)
        val trio = ChatAlbum.layout(listOf(0.7, 1.0, 1.0), 300.0)
        assertEquals(trio.tiles[1].x, trio.tiles[2].x, 0.01)
        // Десять кадров не сужаются под предел высоты.
        val ten = ChatAlbum.layout(List(10) { 1.6 }, 300.0)
        assertEquals(300.0, ten.width, 0.01)
        assertEquals(10, ten.tiles.size)
    }
}
