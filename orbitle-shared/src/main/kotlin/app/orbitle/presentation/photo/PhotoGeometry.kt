package app.orbitle.presentation.photo

import kotlin.math.*

/** Drag фиксирует исходную рамку, поэтому перемещение не накапливает ошибку. */
class PhotoCropDrag(private val rect: PhotoCrop, private val start: PhotoPoint, thresholdX: Float, thresholdY: Float) {
    private val left = abs(start.x-rect.left) < thresholdX
    private val right = !left && abs(start.x-rect.right) < thresholdX
    private val top = abs(start.y-rect.top) < thresholdY
    private val bottom = !top && abs(start.y-rect.bottom) < thresholdY
    private val move = !left && !right && !top && !bottom && start.x in rect.left..rect.right && start.y in rect.top..rect.bottom
    fun update(point: PhotoPoint): PhotoCrop {
        if(move) {
            val dx = (point.x-start.x).coerceIn(-rect.left,1-rect.right)
            val dy = (point.y-start.y).coerceIn(-rect.top,1-rect.bottom)
            return PhotoCrop(rect.left+dx,rect.top+dy,rect.right+dx,rect.bottom+dy)
        }
        if(!left && !right && !top && !bottom) return PhotoCrop.between(start,point) ?: rect
        return PhotoCrop(
            if(left) point.x.coerceAtMost(rect.right-.01f) else rect.left,
            if(top) point.y.coerceAtMost(rect.bottom-.01f) else rect.top,
            if(right) point.x.coerceAtLeast(rect.left+.01f) else rect.right,
            if(bottom) point.y.coerceAtLeast(rect.top+.01f) else rect.bottom,
        )
    }
}

/** Перенос позиции текста из текущего кадра обратно в кадр, где он был добавлен. */
fun PhotoEditHistory.textPoint(id: String, displayed: PhotoPoint, original: PhotoSize): PhotoPoint {
    val commands = resolved
    val index = commands.indexOfFirst { it is PhotoEdit.Text && it.id == id }
    if(index < 0) return displayed
    var size = original
    val sizes = commands.map { edit ->
        val before = size
        size = when(edit) {
            is PhotoEdit.Crop -> edit.rect.pixels(size).let { PhotoSize(it.width,it.height) }
            is PhotoEdit.Rotate -> PhotoSize(size.height,size.width)
            else -> size
        }
        before
    }
    var x = displayed.x; var y = displayed.y
    for(i in commands.lastIndex downTo index+1) {
        when(val edit = commands[i]) {
            is PhotoEdit.Crop -> { x = edit.rect.left + x*(edit.rect.right-edit.rect.left); y = edit.rect.top + y*(edit.rect.bottom-edit.rect.top) }
            is PhotoEdit.Rotate -> { val oldX = x; x = if(edit.clockwise) y else 1-y; y = if(edit.clockwise) 1-oldX else oldX }
            PhotoEdit.Flip -> x = 1-x
            is PhotoEdit.Straighten -> {
                val w = sizes[i].width.toFloat(); val h = sizes[i].height.toFloat()
                val a = Math.toRadians(edit.degrees.toDouble()).toFloat(); val c = cos(a); val s = sin(a)
                val scale = max(abs(c)+h/w*abs(s),abs(c)+w/h*abs(s))
                val px = (x-.5f)*w/scale; val py = (y-.5f)*h/scale
                x = (px*c+py*s)/w+.5f; y = (-px*s+py*c)/h+.5f
            }
            else -> Unit
        }
    }
    return PhotoPoint(x.coerceIn(0f,1f),y.coerceIn(0f,1f))
}
