package app.orbitle.presentation.photo

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream

class PhotoEditsTest {
    @Test fun cropAndRotationKeepValidPixelDimensions() {
        val history = PhotoEditHistory().add(PhotoEdit.Rotate()).add(PhotoEdit.Crop(PhotoCrop(.25f,0f,.75f,1f)))
        assertEquals(PhotoSize(200,800),history.size(PhotoSize(800,400)))
        assertEquals(PixelCrop(0,0,1,1),PhotoCrop(.999f,.999f,1f,1f).pixels(PhotoSize(1,1)))
        assertEquals(PhotoSize(800,400),history.undo().undo().size(PhotoSize(800,400)))
        assertEquals(history.edits,history.undo().redo().edits)
    }

    @Test fun textEditsCanBeChangedAndUndoneWithoutChangingOrder() {
        val text = PhotoEdit.Text("До",PhotoPoint(.2f,.3f),-1,.1f,id="text")
        val base = PhotoEditHistory().add(text).add(PhotoEdit.Rotate())
        val changed = base.add(PhotoEdit.ReplaceText(text.copy(text="После")))
        assertEquals("После",(changed.resolved.first() as PhotoEdit.Text).text)
        assertEquals(base.resolved,changed.undo().resolved)
        val removed = changed.add(PhotoEdit.RemoveText("text"))
        assertEquals(listOf(PhotoEdit.Rotate()),removed.resolved)
        assertEquals(changed.resolved,removed.undo().resolved)
        assertEquals(PhotoPoint(.3f,.8f),base.textPoint("text",PhotoPoint(.2f,.3f),PhotoSize(800,400)))
    }

    @Test fun cropCanMoveWithoutChangingExtentOrLeavingImage() {
        val drag=PhotoCropDrag(PhotoCrop(.2f,.2f,.8f,.8f),PhotoPoint(.5f,.5f),.02f,.02f)
        val moved=drag.update(PhotoPoint(1f,1f))
        assertEquals(1f,moved.right,0.00001f);assertEquals(1f,moved.bottom,0.00001f)
        assertEquals(.6f,moved.right-moved.left,.00001f)
    }

    @Test fun filterStrengthAndNeutralAdjustmentsPreserveColors() {
        val pixel=0x7f4f91e3
        PhotoFilter.entries.forEach { assertEquals(pixel,it.pixel(pixel,0f));assertEquals(0x7f,it.pixel(pixel) ushr 24) }
        val gray=PhotoFilter.MONO.pixel(pixel)
        assertEquals((gray ushr 16) and 255,(gray ushr 8) and 255)
        val processor=PhotoAdjustments().processor()
        for(value in listOf(0xff000000.toInt(),-1,0xff123456.toInt(),0xff8092ac.toInt())) assertEquals(value,processor.pixel(value,3,5,10,10))
        assertArrayEquals(IntArray(15){0xff124578.toInt()},PhotoPixels.blur(IntArray(15){0xff124578.toInt()},5,3,6))
    }

    @Test fun exifHandlesAllOrientationsAndTruncatedInput() {
        val destinations=(1..8).map { orientation ->
            val positions=(0 until 2).flatMap { y -> (0 until 3).map { x -> PhotoExif.position(orientation,x,y,3,2) } }
            assertEquals(6,positions.toSet().size)
            positions
        }
        assertEquals(1 to 0,destinations[5][0])
        val segment=byteArrayOf(69,120,105,102,0,0,73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,6,0,0,0,0,0,0,0)
        val jpeg=byteArrayOf(-1,-40,-1,-31,0,(segment.size+2).toByte())+segment+byteArrayOf(-1,-39)
        assertEquals(6,PhotoExif.orientation(ByteArrayInputStream(jpeg)))
        assertEquals(1,PhotoExif.orientation(ByteArrayInputStream(jpeg.copyOf(12))))
    }
}
