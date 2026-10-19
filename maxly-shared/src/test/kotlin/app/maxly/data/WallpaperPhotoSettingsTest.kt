package app.maxly.data

import app.maxly.domain.ChatWallpaperChoice
import app.maxly.domain.ResolvedWallpaper
import app.maxly.domain.WallpaperPhoto
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class WallpaperPhotoSettingsTest {
    @get:Rule val temp = TemporaryFolder()

    /** Хранилище без своего удаления: `remove` пишет пустую строку. */
    private class Memory : PreferenceStore {
        val values = mutableMapOf<String, String>()
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) {
            values[key] = value
        }
    }

    private fun photo(settings: WallpaperPhotoSettings): File = settings.newFile().apply { writeText("jpg") }

    @Test
    fun globalPhotoDimAndBlurSurviveRestart() {
        val store = Memory()
        val dir = temp.newFolder("wallpapers")
        val settings = WallpaperPhotoSettings(store, dir)
        assertEquals(ResolvedWallpaper.Preset, settings.resolve("1", "chat"))
        val file = photo(settings)
        settings.setGlobal(file.path)
        settings.setDim(90)
        settings.setBlur(true)
        val again = WallpaperPhotoSettings(store, dir)
        assertEquals(WallpaperPhoto(file.path, 60, true), again.state.value.globalPhoto)
        assertEquals(ResolvedWallpaper.Photo(WallpaperPhoto(file.path, 60, true)), again.resolve("1", "chat"))
        assertEquals(ResolvedWallpaper.Photo(WallpaperPhoto(file.path, 60, true)), again.resolve("1", null))
    }

    @Test
    fun replacingAndResettingDeletesOldCopies() {
        val dir = temp.newFolder("wallpapers")
        val settings = WallpaperPhotoSettings(Memory(), dir)
        val first = photo(settings)
        settings.setGlobal(first.path)
        val second = photo(settings)
        settings.setGlobal(second.path)
        assertFalse(first.exists())
        assertTrue(second.exists())
        settings.resetGlobal()
        assertFalse(second.exists())
        assertEquals(null, settings.state.value.global)
        assertEquals(ResolvedWallpaper.Preset, settings.resolve("1", "chat"))
    }

    @Test
    fun filesOutsideTheFolderAreNeverDeleted() {
        val settings = WallpaperPhotoSettings(Memory(), temp.newFolder("wallpapers"))
        val foreign = temp.newFile("user.jpg")
        settings.setGlobal(foreign.path)
        settings.resetGlobal()
        assertTrue(foreign.exists())
    }

    @Test
    fun chatChoiceWinsOverGlobalAndIsKeptPerAccount() {
        val store = Memory()
        val dir = temp.newFolder("wallpapers")
        val settings = WallpaperPhotoSettings(store, dir)
        val global = photo(settings)
        settings.setGlobal(global.path)
        val own = photo(settings)
        settings.setChat("1", "chat", ChatWallpaperChoice.Photo(own.path))
        assertEquals(own.path, (settings.resolve("1", "chat") as ResolvedWallpaper.Photo).photo.path)
        assertEquals(global.path, (settings.resolve("1", "other") as ResolvedWallpaper.Photo).photo.path)
        assertEquals(global.path, (settings.resolve("2", "chat") as ResolvedWallpaper.Photo).photo.path)
        assertEquals("wallpaper.photo.chat.1.chat", WallpaperPhotoSettings.chatKey("1", "chat"))
        assertEquals(own.path, store.values[WallpaperPhotoSettings.chatKey("1", "chat")])

        settings.setChat("1", "chat", ChatWallpaperChoice.Plain)
        assertFalse(own.exists())
        assertEquals(ResolvedWallpaper.Plain, settings.resolve("1", "chat"))
        assertEquals(ChatWallpaperChoice.Plain, WallpaperPhotoSettings(store, dir).chatChoice("1", "chat"))

        settings.setChat("1", "chat", ChatWallpaperChoice.Global)
        assertEquals(ChatWallpaperChoice.Global, settings.chatChoice("1", "chat"))
        assertEquals(global.path, (settings.resolve("1", "chat") as ResolvedWallpaper.Photo).photo.path)
        settings.resetGlobal()
        assertEquals(ResolvedWallpaper.Preset, settings.resolve("1", "chat"))
    }

    @Test
    fun everyChangeBumpsRevision() {
        val settings = WallpaperPhotoSettings(Memory(), temp.newFolder("wallpapers"))
        val start = settings.state.value.revision
        settings.setChat("1", "chat", ChatWallpaperChoice.Plain)
        assertEquals(start + 1, settings.state.value.revision)
    }
}
