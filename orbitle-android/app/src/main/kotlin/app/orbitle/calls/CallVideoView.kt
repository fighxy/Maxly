package app.orbitle.calls

import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.orbitle.ui.calls.CallVideoRenderer
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer

/** Видео звонка на Android: `SurfaceViewRenderer` на общем контексте EGL. */
val AndroidCallVideo = CallVideoRenderer { trackId, fill, modifier ->
    val tracks by CallVideoRegistry.tracks.collectAsStateWithLifecycle()
    val entry = tracks[trackId]
    val context = LocalContext.current
    val renderer = remember {
        SurfaceViewRenderer(context).apply {
            init(AndroidWebRtc.egl.eglBaseContext, null)
            setEnableHardwareScaler(true)
        }
    }
    DisposableEffect(renderer) {
        onDispose { renderer.release() }
    }
    val track = entry?.track
    DisposableEffect(track, renderer) {
        if (track == null) return@DisposableEffect onDispose {}
        runCatching { track.addSink(renderer) }
        onDispose { runCatching { track.removeSink(renderer) } }
    }
    AndroidView(
        factory = { renderer },
        update = { view ->
            view.setScalingType(if (fill) RendererCommon.ScalingType.SCALE_ASPECT_FILL else RendererCommon.ScalingType.SCALE_ASPECT_FIT)
            view.setMirror(entry?.mirrored == true)
        },
        modifier = modifier,
    )
}
