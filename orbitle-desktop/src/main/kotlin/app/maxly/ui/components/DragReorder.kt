package app.maxly.ui.components

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.maxly.presentation.common.ListOrder

/**
 * Перетаскивание строки списка за ручку: рабочий порядок живёт только на экране, пока палец не
 * отпущен. Строка едет за пальцем, соседи меняются местами, когда центр строки заходит на них.
 * Ключи строк в [list] — id из порядка; строки с другими ключами не участвуют.
 */
class DragReorder(private val list: LazyListState) {
    var order by mutableStateOf<List<String>?>(null)
        private set
    var draggedId by mutableStateOf<String?>(null)
        private set
    var offset by mutableFloatStateOf(0f)
        private set
    /** Новое перетаскивание обрывает доводку прошлого. */
    private var settleToken = 0

    fun start(id: String, current: List<String>) {
        if (id !in current) return
        settleToken++
        order = current
        draggedId = id
        offset = 0f
    }

    fun drag(dy: Float) {
        val id = draggedId ?: return
        val ids = order ?: return
        offset += dy
        val visible = list.layoutInfo.visibleItemsInfo
        val dragged = visible.firstOrNull { it.key == id } ?: return
        val center = dragged.offset + offset + dragged.size / 2f
        val target = visible.firstOrNull { info ->
            info.key != id && info.key in ids && center >= info.offset && center < info.offset + info.size
        } ?: return
        val from = ids.indexOf(id)
        val to = ids.indexOf(target.key)
        // Раскладка ещё не догнала прошлый обмен — ждём следующего кадра.
        if (target.index - dragged.index != to - from) return
        val landed = if (to > from) target.offset + target.size - dragged.size else target.offset
        order = ListOrder.moved(ids, from, to)
        offset += dragged.offset - landed
    }

    /** Отпустили: рабочий порядок для модели (или `null`, если тянуть было нечего). */
    fun finish(): List<String>? {
        val result = order
        order = null
        return result
    }

    /** Строка плавно встаёт на место, потом перестаёт быть перетаскиваемой. */
    suspend fun settle() {
        if (draggedId == null) return
        val token = ++settleToken
        animate(offset, 0f, animationSpec = tween(150)) { value, _ -> if (token == settleToken) offset = value }
        if (token == settleToken) draggedId = null
    }
}
