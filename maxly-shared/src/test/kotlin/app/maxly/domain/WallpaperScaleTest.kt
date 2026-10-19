package app.maxly.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WallpaperScaleTest {
    @Test
    fun longestSideIsCappedAndProportionsKept() {
        assertEquals(2560 to 1920, WallpaperScale.target(4032, 3024))
        assertEquals(1440 to 2560, WallpaperScale.target(3024, 5376))
        assertEquals(2560 to 2560, WallpaperScale.target(8000, 8000))
        assertEquals(2560 to 1, WallpaperScale.target(100_000, 10))
    }

    @Test
    fun smallImagesAreNotUpscaled() {
        assertEquals(800 to 600, WallpaperScale.target(800, 600))
        assertEquals(2560 to 100, WallpaperScale.target(2560, 100))
    }

    @Test
    fun sampleSizeStaysAboveTarget() {
        assertEquals(1, WallpaperScale.sampleSize(4032, 3024))
        assertEquals(2, WallpaperScale.sampleSize(6000, 4000))
        assertEquals(4, WallpaperScale.sampleSize(12000, 9000))
        assertEquals(1, WallpaperScale.sampleSize(100, 100))
    }

    @Test
    fun exifRotationSwapsSides() {
        assertFalse(WallpaperScale.swapsSides(1))
        assertFalse(WallpaperScale.swapsSides(3))
        assertTrue(WallpaperScale.swapsSides(6))
        assertTrue(WallpaperScale.swapsSides(8))
        assertEquals(3024 to 4032, WallpaperScale.oriented(4032, 3024, 6))
        assertEquals(4032 to 3024, WallpaperScale.oriented(4032, 3024, 0))
    }

    @Test
    fun centerCropFillsWithoutStretching() {
        // Альбомное фото в высоком окне: режутся бока, масштаб один на обе оси.
        val crop = WallpaperScale.centerCrop(2560, 1920, 400, 800)
        assertEquals(800.0 / 1920, crop.scale, 1e-9)
        assertEquals(1920.0, crop.height, 1e-6)
        assertEquals(960.0, crop.width, 1e-6)
        assertEquals(800.0, crop.left, 1e-6)
        assertEquals(0.0, crop.top, 1e-6)
        // Окно стало шире: режутся верх и низ.
        val wide = WallpaperScale.centerCrop(2560, 1920, 1600, 600)
        assertEquals(0.0, wide.left, 1e-6)
        assertEquals((1920 - 960) / 2.0, wide.top, 1e-6)
    }

    @Test
    fun dimIsClamped() {
        assertEquals(0, WallpaperScale.clampDim(-5))
        assertEquals(60, WallpaperScale.clampDim(80))
        assertEquals(30, WallpaperScale.clampDim(30))
    }
}
