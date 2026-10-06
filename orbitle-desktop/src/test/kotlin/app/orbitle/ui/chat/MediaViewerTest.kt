package app.orbitle.ui.chat

import androidx.compose.ui.geometry.Size
import org.junit.Assert.assertEquals
import org.junit.Test

class MediaViewerTest {
    @Test
    fun sidewaysPhotoShrinksToFitTheScreen() {
        val box = Size(800f, 600f)
        // Стоит ровно — без изменений, сколько бы раз ни повернули.
        assertEquals(1f, sidewaysFit(Size(400f, 200f), box, 0), 0.001f)
        assertEquals(1f, sidewaysFit(Size(400f, 200f), box, 2), 0.001f)
        // Вписано 800×400, на боку 400×800: по высоте влезает с 0,75.
        assertEquals(0.75f, sidewaysFit(Size(400f, 200f), box, 1), 0.001f)
        assertEquals(0.75f, sidewaysFit(Size(400f, 200f), box, 7), 0.001f)
        // Квадрат на боку тот же, крупнее не делается.
        assertEquals(1f, sidewaysFit(Size(300f, 300f), box, 1), 0.001f)
        // Размер картинки ещё неизвестен.
        assertEquals(1f, sidewaysFit(Size.Unspecified, box, 1), 0.001f)
    }
}
