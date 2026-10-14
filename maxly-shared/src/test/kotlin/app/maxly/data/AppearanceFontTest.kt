package app.maxly.data

import app.maxly.domain.AppFont
import app.maxly.domain.FontWeightScale
import org.junit.Assert.assertEquals
import org.junit.Test

class AppearanceFontTest {
    private class Memory : PreferenceStore {
        val values = mutableMapOf<String, String>()
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) {
            values[key] = value
        }
    }

    @Test
    fun fontAndWeightAreKeptAndClamped() {
        val store = Memory()
        val settings = AppearanceSettings(store)
        assertEquals(AppFont.SYSTEM, settings.state.value.font)
        assertEquals(400, settings.state.value.fontWeight)
        settings.setFont(AppFont.ONEST)
        settings.setFontWeight(900)
        assertEquals(600, settings.state.value.fontWeight)
        val again = AppearanceSettings(store).state.value
        assertEquals(AppFont.ONEST, again.font)
        assertEquals(600, again.fontWeight)
        store.values["appearance.font"] = "COMIC"
        store.values["appearance.fontWeight"] = "abc"
        val broken = AppearanceSettings(store).state.value
        assertEquals(AppFont.SYSTEM, broken.font)
        assertEquals(400, broken.fontWeight)
        assertEquals("Onest, 17 пт", again.fontSummary)
    }

    @Test
    fun weightShiftsEveryStyleWithinTheFontAxis() {
        assertEquals(400, FontWeightScale.axis(AppFont.INTER, 400, 400))
        assertEquals(650, FontWeightScale.axis(AppFont.INTER, 600, 450))
        assertEquals(300, FontWeightScale.axis(AppFont.INTER, 400, 300))
        // У Golos Text нет толщины тоньше 400, у Manrope — толще 800.
        assertEquals(400, FontWeightScale.axis(AppFont.GOLOS, 400, 300))
        assertEquals(800, FontWeightScale.axis(AppFont.MANROPE, 700, 600))
        // Системный — сотнями.
        assertEquals(500, FontWeightScale.axis(AppFont.SYSTEM, 400, 460))
        assertEquals(400, FontWeightScale.axis(AppFont.SYSTEM, 400, 440))
        assertEquals("Обычный · 400", FontWeightScale.caption(400))
        assertEquals("Полужирный · 600", FontWeightScale.caption(700))
        assertEquals("Светлый · 300", FontWeightScale.caption(300))
    }
}
