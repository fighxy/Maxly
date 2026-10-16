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
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
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
 * Записанный кружок на просмотре: выбранный кусок играет по кругу без звука,
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

/**
 * Голосовое на просмотре вместо поля ввода: корзина, прослушивание выбранного
 * куска, волна с ручками обрезки и длина куска.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun VoiceTrimBar(
    review: RecordingController.VoiceReview,
    onTrim: (Float, Float) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val path = review.recording.path
    val player = remember(path) { ExoPlayer.Builder(context).build() }
    var playing by remember(path) { mutableStateOf(false) }
    var position by remember(path) { mutableStateOf(0f) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                playing = isPlaying
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    player.pause()
                    player.seekTo(0)
                }
            }
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    // Новый кусок — новый клип: ручку тянут, плеер встаёт и ждёт.
    LaunchedEffect(player, review.fromMs, review.toMs) {
        player.pause()
        val clip = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(review.fromMs)
            .setEndPositionMs(review.toMs)
            .build()
        player.setMediaItem(MediaItem.Builder().setUri(android.net.Uri.fromFile(File(path))).setClippingConfiguration(clip).build())
        player.prepare()
    }
    LaunchedEffect(player, playing) {
        while (playing) {
            val length = (review.toMs - review.fromMs).coerceAtLeast(1)
            position = review.start + (review.end - review.start) * (player.currentPosition.toFloat() / length).coerceIn(0f, 1f)
            delay(50)
        }
    }
    Row(
        modifier
            .height(48.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(start = 2.dp, end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onDelete) {
            Icon(Icons.Outlined.Delete, "Удалить голосовое", tint = MaterialTheme.colorScheme.error)
        }
        Box(
            Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary)
                .clickable { if (player.isPlaying) player.pause() else player.play() }
                .semantics { contentDescription = if (playing) "Пауза" else "Прослушать" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                null,
                Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onPrimary,
            )
        }
        VoiceWaveTrim(review, if (playing) position else -1f, onTrim, Modifier.weight(1f).height(32.dp).padding(horizontal = 8.dp))
        androidx.compose.material3.Text(
            app.maxly.presentation.chat.CallBubbleText.clock(review.selectedMs),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** Волна голосового с ручками обрезки; [position] — место воспроизведения (доля) или `-1`. */
@Composable
private fun VoiceWaveTrim(review: RecordingController.VoiceReview, position: Float, onTrim: (Float, Float) -> Unit, modifier: Modifier) {
    val current by rememberUpdatedState(review)
    val accent = MaterialTheme.colorScheme.primary
    val ink = MaterialTheme.colorScheme.onSurface
    val bars = review.recording.waveform.ifEmpty { List(40) { 10 } }
    val handle = 10.dp
    BoxWithConstraints(modifier) {
        val widthPx = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val density = LocalDensity.current
        Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            bars.forEachIndexed { index, value ->
                val fraction = (index + 0.5f) / bars.size
                val inside = fraction in review.start..review.end
                val color = when {
                    position >= 0f && inside && fraction <= position -> accent
                    inside -> ink.copy(alpha = 0.55f)
                    else -> ink.copy(alpha = 0.18f)
                }
                Box(
                    Modifier
                        .weight(1f)
                        .padding(horizontal = 0.5.dp)
                        .height((32f * (value.coerceIn(8, 120) / 120f)).dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(color),
                )
            }
        }
        val left = review.start * widthPx
        val right = review.end * widthPx
        val leftDp = with(density) { left.toDp() }
        val rightDp = with(density) { right.toDp() }
        Box(
            Modifier
                .offset { IntOffset(left.roundToInt(), 0) }
                .width((rightDp - leftDp).coerceAtLeast(handle * 2))
                .fillMaxHeight()
                .border(2.dp, accent, RoundedCornerShape(5.dp)),
        )
        TrimHandle(accent, handle, Modifier.offset { IntOffset(left.roundToInt(), 0) }.pointerInput(widthPx) {
            detectHorizontalDragGestures { change, dx ->
                change.consume()
                onTrim(current.start + dx / widthPx, current.end)
            }
        }.semantics { contentDescription = "Начало голосового" })
        TrimHandle(accent, handle, Modifier.offset { IntOffset((right - handle.toPx()).roundToInt(), 0) }.pointerInput(widthPx) {
            detectHorizontalDragGestures { change, dx ->
                change.consume()
                onTrim(current.start, current.end + dx / widthPx)
            }
        }.semantics { contentDescription = "Конец голосового" })
    }
}
