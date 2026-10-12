package app.maxly.ui.chat

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import androidx.media3.ui.compose.SURFACE_TYPE_TEXTURE_VIEW
import app.maxly.presentation.chat.RecordingController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.roundToInt

/**
 * Записанный кружок на просмотре, как в Telegram: выбранный кусок играет по кругу без звука,
 * касание включает звук. Кусок меняется ручками полосы ([NoteTrimBar]); плеер берёт новый,
 * когда ручки остановились.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun NoteReviewCircle(review: RecordingController.NoteReview, modifier: Modifier) {
    val context = LocalContext.current
    val path = review.recording.path
    val player = remember(path) {
        ExoPlayer.Builder(context).build().apply {
            repeatMode = Player.REPEAT_MODE_ONE
            volume = 0f
        }
    }
    var muted by remember(path) { mutableStateOf(true) }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(player, review.fromMs, review.toMs) {
        // Ручку ещё тянут: кусок перезапускается, когда она встанет.
        delay(250)
        val clip = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(review.fromMs)
            .setEndPositionMs(review.toMs)
            .build()
        player.setMediaItem(MediaItem.Builder().setUri(android.net.Uri.fromFile(File(path))).setClippingConfiguration(clip).build())
        player.prepare()
        player.playWhenReady = true
    }
    Box(
        modifier
            .clip(CircleShape)
            .background(Color.Black)
            .clickable {
                muted = !muted
                player.volume = if (muted) 0f else 1f
            }
            .semantics { contentDescription = if (muted) "Включить звук кружка" else "Выключить звук кружка" },
    ) {
        ContentFrame(
            player = player,
            modifier = Modifier.fillMaxSize(),
            surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
            contentScale = ContentScale.Crop,
            shutter = {},
        )
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 14.dp)
                .size(30.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (muted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                null,
                Modifier.size(16.dp),
                tint = Color.White,
            )
        }
    }
}

/** Полоса просмотра вместо поля ввода: корзина и кадры кружка с ручками обрезки. */
@Composable
fun NoteTrimBar(
    review: RecordingController.NoteReview,
    onTrim: (Float, Float) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier,
) {
    Row(
        modifier
            .height(48.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(start = 2.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onDelete) {
            Icon(Icons.Outlined.Delete, "Удалить кружок", tint = MaterialTheme.colorScheme.error)
        }
        TrimStrip(review, onTrim, Modifier.weight(1f).height(36.dp))
    }
}

@Composable
private fun TrimStrip(review: RecordingController.NoteReview, onTrim: (Float, Float) -> Unit, modifier: Modifier) {
    val frames by produceState(emptyList<Bitmap>(), review.recording.path) {
        value = withContext(Dispatchers.IO) { thumbnails(review.recording.path, review.recording.durationMs) }
    }
    val current by rememberUpdatedState(review)
    val accent = MaterialTheme.colorScheme.primary
    val handle = 12.dp
    BoxWithConstraints(modifier.clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.2f))) {
        val widthPx = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val density = LocalDensity.current
        Row(Modifier.fillMaxSize()) {
            frames.forEach { frame ->
                Image(frame.asImageBitmap(), null, Modifier.weight(1f).fillMaxHeight(), contentScale = ContentScale.Crop)
            }
        }
        val left = review.start * widthPx
        val right = review.end * widthPx
        val leftDp = with(density) { left.toDp() }
        val rightDp = with(density) { right.toDp() }
        // Вне выбранного куска — тень.
        Box(Modifier.width(leftDp).fillMaxHeight().background(Color.Black.copy(alpha = 0.55f)))
        Box(Modifier.offset { IntOffset(right.roundToInt(), 0) }.width(maxWidth - rightDp).fillMaxHeight().background(Color.Black.copy(alpha = 0.55f)))
        Box(
            Modifier
                .offset { IntOffset(left.roundToInt(), 0) }
                .width((rightDp - leftDp).coerceAtLeast(handle * 2))
                .fillMaxHeight()
                .border(3.dp, accent, RoundedCornerShape(6.dp)),
        )
        TrimHandle(accent, handle, Modifier.offset { IntOffset(left.roundToInt(), 0) }.pointerInput(widthPx) {
            detectHorizontalDragGestures { change, dx ->
                change.consume()
                onTrim(current.start + dx / widthPx, current.end)
            }
        }.semantics { contentDescription = "Начало кружка" })
        TrimHandle(accent, handle, Modifier.offset { IntOffset((right - handle.toPx()).roundToInt(), 0) }.pointerInput(widthPx) {
            detectHorizontalDragGestures { change, dx ->
                change.consume()
                onTrim(current.start, current.end + dx / widthPx)
            }
        }.semantics { contentDescription = "Конец кружка" })
    }
}

@Composable
private fun TrimHandle(color: Color, width: androidx.compose.ui.unit.Dp, modifier: Modifier) {
    Box(
        modifier
            .width(width)
            .fillMaxHeight()
            .clip(RoundedCornerShape(4.dp))
            .background(color),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 3.dp, height = 14.dp).clip(RoundedCornerShape(2.dp)).background(Color.White))
    }
}

/** Кадры для полосы обрезки. */
private fun thumbnails(path: String, durationMs: Long, count: Int = 8): List<Bitmap> {
    val retriever = MediaMetadataRetriever()
    return try {
        retriever.setDataSource(path)
        (0 until count).mapNotNull { index ->
            val us = durationMs * 1_000 * (2 * index + 1) / (2 * count)
            retriever.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { frame ->
                val side = 96
                val scale = side.toFloat() / maxOf(frame.width, frame.height)
                Bitmap.createScaledBitmap(frame, (frame.width * scale).toInt().coerceAtLeast(1), (frame.height * scale).toInt().coerceAtLeast(1), true)
            }
        }
    } catch (_: Exception) {
        emptyList()
    } finally {
        retriever.release()
    }
}
