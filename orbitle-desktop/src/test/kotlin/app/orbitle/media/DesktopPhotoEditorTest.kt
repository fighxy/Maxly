package app.orbitle.media

import app.orbitle.domain.OutgoingFile
import app.orbitle.presentation.photo.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.awt.Color
import java.awt.image.BufferedImage
import java.nio.file.Files
import javax.imageio.ImageIO

class DesktopPhotoEditorTest {
    private fun image() = BufferedImage(80,40,BufferedImage.TYPE_INT_RGB).apply {
        val g=createGraphics();g.color=Color.BLUE;g.fillRect(0,0,80,40);g.dispose()
    }

    @Test fun eraserRemovesAnnotationsAndLeavesPhoto() = runBlocking {
        val stroke=PhotoEdit.Stroke(listOf(PhotoPoint(.2f,.5f),PhotoPoint(.8f,.5f)),Color.RED.rgb,.2f)
        val painted=DesktopPhotoEditor.render(image(),listOf(stroke))
        assertEquals(Color.RED.rgb,painted.getRGB(40,20))
        val erased=DesktopPhotoEditor.render(image(),listOf(stroke,stroke.copy(brush=PhotoBrush.ERASER)))
        assertEquals(Color.BLUE.rgb,erased.getRGB(40,20))
        assertEquals(Color.BLUE.rgb,erased.getRGB(0,0))
    }

    @Test fun geometryTransformsPhotoAndAnnotationsTogether() = runBlocking {
        val stroke=PhotoEdit.Stroke(listOf(PhotoPoint(.25f,.5f)),Color.RED.rgb,.2f)
        val result=DesktopPhotoEditor.render(image(),listOf(stroke,PhotoEdit.Rotate(),PhotoEdit.Flip))
        assertEquals(40,result.width);assertEquals(80,result.height)
        assertEquals(Color.RED.rgb,result.getRGB(20,20))
        val cropped=DesktopPhotoEditor.render(image(),listOf(PhotoEdit.Crop(PhotoCrop(.25f,0f,.75f,1f))))
        assertEquals(40,cropped.width);assertEquals(40,cropped.height)
    }

    @Test fun correctionDoesNotTintTextAndDrawing() = runBlocking {
        val stroke=PhotoEdit.Stroke(listOf(PhotoPoint(.5f,.5f)),Color.RED.rgb,.2f)
        val result=DesktopPhotoEditor.render(image(),listOf(stroke,PhotoEdit.Filter(PhotoFilter.MONO)))
        assertEquals(Color.RED.rgb,result.getRGB(40,20))
        val pixel=result.getRGB(0,0)
        assertEquals((pixel ushr 16) and 255,pixel and 255)
    }

    @Test fun straightenFillsFrameAndBlurIsDeterministic() = runBlocking {
        val result=DesktopPhotoEditor.render(image(),listOf(PhotoEdit.Straighten(30f),PhotoEdit.Adjust(PhotoAdjustments(blur=.3f))))
        assertEquals(80,result.width);assertEquals(40,result.height)
        assertEquals(Color.BLUE.rgb,result.getRGB(0,0))
    }

    @Test fun exportWritesSeparateJpegAndActualMetadata() = runBlocking {
        val folder=Files.createTempDirectory("orbitle-photo-test").toFile()
        try {
            val original=java.io.File(folder,"original.png");ImageIO.write(image(),"png",original)
            val bytes=original.readBytes()
            val source=DesktopPhotoEditor.load(OutgoingFile(original.path,original.name,OutgoingFile.Kind.PHOTO))
            val output=source.export(listOf(PhotoEdit.Rotate()))
            val decoded=ImageIO.read(java.io.File(output.path))
            assertEquals(40,output.width);assertEquals(80,output.height)
            assertEquals(output.width,decoded.width);assertEquals(output.height,decoded.height)
            assertEquals(java.io.File(output.path).length(),output.size)
            assertNotEquals(original.path,output.path);assertArrayEquals(bytes,original.readBytes())
        } finally { folder.deleteRecursively() }
    }
}
