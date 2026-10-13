package app.maxly.ui.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import app.maxly.presentation.media.HeroRect

/**
 * Где в ленте стоят плитки фото и видео: просмотр вылетает из плитки и возвращается в неё.
 * Рамки пишутся при каждом сдвиге ленты и лежат вне состояния Compose; перерисовку вызывает
 * только [hiddenId] — плитка, которая сейчас в просмотре и в ленте не видна.
 */
object MediaTiles {
    /** Плитка в пикселях экрана, модель её картинки для Coil (та же — из кэша) и скругление, px. */
    data class Tile(val bounds: HeroRect, val model: Any?, val cornerRadius: Float)

    private val tiles = HashMap<String, Tile>()

    /** Плитка, открытая в просмотре: на её месте пусто, пока просмотр не закрылся. */
    var hiddenId by mutableStateOf<String?>(null)

    fun update(id: String, tile: Tile) { tiles[id] = tile }

    fun remove(id: String) { tiles.remove(id) }

    fun tile(id: String): Tile? = tiles[id]
}

/** Плитка [id] сообщает, где она, и прячется, пока открыта в просмотре. */
fun Modifier.mediaTile(id: String, model: Any?, cornerRadius: Float): Modifier =
    onGloballyPositioned { coordinates ->
        // Не обрезанная краем ленты рамка: кадр должен лететь в плитку целиком.
        val origin = coordinates.positionOnScreen()
        val size = coordinates.size
        MediaTiles.update(id, MediaTiles.Tile(HeroRect(origin.x, origin.y, size.width.toFloat(), size.height.toFloat()), model, cornerRadius))
    }.alpha(if (MediaTiles.hiddenId == id) 0f else 1f)
