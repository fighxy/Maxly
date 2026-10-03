package app.orbitle.ui.res

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.toComposeImageBitmap
import app.orbitle.DRAWABLE_FILES
import app.orbitle.STRING_TABLE
import org.jetbrains.skia.Image

@Composable
fun stringResource(id: Int): String = STRING_TABLE.getValue(id)

/** Картинка из `src/main/resources/images`. */
@Composable
fun painterResource(id: Int): Painter {
    val name = DRAWABLE_FILES.getValue(id)
    return remember(name) {
        val bytes = Loader.javaClass.classLoader.getResourceAsStream("images/$name")?.use { it.readBytes() }
            ?: error("Нет ресурса images/$name")
        BitmapPainter(Image.makeFromEncoded(bytes).toComposeImageBitmap())
    }
}

private object Loader
