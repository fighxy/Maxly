package app.orbitle.presentation.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QrLoginTest {
    @Test
    fun `login link is trimmed and plain text is rejected`() {
        assertEquals("https://max.ru/:login/abc", QrLogin.loginLink("  https://max.ru/:login/abc\n"))
        assertNull(QrLogin.loginLink("   "))
        assertNull(QrLogin.loginLink("привет мир"))
    }
}
