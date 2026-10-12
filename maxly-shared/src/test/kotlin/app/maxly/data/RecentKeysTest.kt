package app.maxly.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecentKeysTest {
    @Test
    fun repeatsAreDroppedAndOldKeysForgotten() {
        val keys = RecentKeys(2)
        assertTrue(keys.add("a"))
        assertFalse(keys.add("a"))
        assertTrue(keys.add("b"))
        assertTrue(keys.add("c"))
        // «a» вытеснен — снова новый.
        assertTrue(keys.add("a"))
        assertFalse(keys.add("c"))
    }
}
