package app.orbitle.calls

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.layout.ContentScale
import app.orbitle.ui.calls.CallVideoRenderer
import dev.onvoid.webrtc.media.FourCC
import dev.onvoid.webrtc.media.video.VideoBufferConverter
import dev.onvoid.webrtc.media.video.VideoFrame
import dev.onvoid.webrtc.media.video.VideoTrack
import dev.onvoid.webrtc.media.video.VideoTrackSink
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.Image as SkiaImage
import org.jetbrains.skia.ImageInfo
import javax.swing.SwingUtilities

/** Видеодорожки идущего звонка по id: экран звонка рисует их по id из `CallState`. */
object CallVideoRegistry {
    private class Entry(val track: VideoTrack, val mirrored: Boolean)

    private val tracks = MutableStateFlow<Map<String, Entry>>(emptyMap())

    internal fun register(track: VideoTrack, mirrored: Boolean) {
        val id = runCatching { track.id }.getOrNull() ?: return
        tracks.update { it + (id to Entry(track, mirrored)) }
    }

    internal fun clear() {
        tracks.value = emptyMap()
    }

    /** Дорожка и зеркалить ли её (своя камера показывается как в зеркале). */
    @Composable
    internal fun lookup(id: String): Pair<VideoTrack, Boolean>? {
        val all by tracks.collectAsState()
        return all[id]?.let { it.track to it.mirrored }
    }
}

/** Кадры дорожки в картинку Compose: не чаще 30 в секунду, лишние пропускаются. */
private class FrameSink(private val onFrame: (ImageBitmap) -> Unit) : VideoTrackSink {
    @Volatile
    private var busy = false
    private var last = 0L
    private var pixels = ByteArray(0)

    override fun onVideoFrame(frame: VideoFrame) {
        val now = System.nanoTime()
        if (busy || now - last < 33_000_000L) return
        last = now
        val buffer = frame.buffer
        val width = buffer.width
        val height = buffer.height
        if (width <= 0 || height <= 0) return
        val size = width * height * 4
        if (pixels.size != size) pixels = ByteArray(size)
        try {
            // libyuv «ARGB» — это B, G, R, A по байтам: так и читает Skia BGRA_8888.
            VideoBufferConverter.convertFromI420(buffer, pixels, FourCC.ARGB)
        } catch (_: Exception) {
            return
        }
        val image = SkiaImage.makeRaster(
            ImageInfo(width, height, ColorType.BGRA_8888, ColorAlphaType.OPAQUE),
            pixels.copyOf(),
            width * 4,
        ).toComposeImageBitmap()
        busy = true
        SwingUtilities.invokeLater {
            busy = false
            onFrame(image)
        }
    }
}

/** Видео звонка на ПК: кадры дорожки WebRTC картинкой. */
val DesktopCallVideo = CallVideoRenderer { trackId, fill, modifier ->
    val found = CallVideoRegistry.lookup(trackId)
    var frame by remember(trackId) { mutableStateOf<ImageBitmap?>(null) }
    val track = found?.first
    DisposableEffect(track) {
        if (track == null) return@DisposableEffect onDispose {}
        val sink = FrameSink { frame = it }
        runCatching { track.addSink(sink) }
        onDispose { runCatching { track.removeSink(sink) } }
    }
    Box(modifier.clipToBounds().background(Color.Black)) {
        frame?.let { image ->
            Image(
                image,
                contentDescription = null,
                contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
                modifier = Modifier.matchParentSize().graphicsLayer { if (found?.second == true) scaleX = -1f },
            )
        }
    }
}
