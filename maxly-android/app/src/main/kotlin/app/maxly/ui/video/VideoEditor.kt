package app.maxly.ui.video

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.transformer.*
import androidx.media3.ui.PlayerView
import app.maxly.domain.OutgoingFile
import kotlinx.coroutines.delay
import java.io.File
import java.util.UUID

@androidx.annotation.OptIn(UnstableApi::class)
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoEditor(file: OutgoingFile, onClose: () -> Unit, onSave: (OutgoingFile) -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val player = remember(file.path) { ExoPlayer.Builder(context).build() }
    var duration by remember(file.path) { mutableLongStateOf(0) }
    var selection by remember(file.path) { mutableStateOf(0f..1f) }
    var muted by remember(file.path) { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var confirmClose by remember { mutableStateOf(false) }
    var transformer by remember { mutableStateOf<Transformer?>(null) }
    var output by remember { mutableStateOf<File?>(null) }
    val changed = selection.start > 0f || selection.endInclusive < 1f || muted
    val start = (selection.start * duration).toLong()
    val end = (selection.endInclusive * duration).toLong()
    val latestSave by rememberUpdatedState(onSave)
    fun close() { if (!busy) { if (changed) confirmClose = true else onClose() } }
    fun preview() { player.seekTo(start); player.play() }
    fun save() {
        if (busy || duration <= 0 || end <= start) return
        if (!changed) { onSave(file); return }
        player.pause(); busy = true; failure = null
        val target = File(context.cacheDir, "video-${UUID.randomUUID()}.mp4")
        output = target
        val item = MediaItem.Builder().setUri(Uri.fromFile(File(file.path)))
            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(start).setEndPositionMs(end).build()).build()
        val edited = EditedMediaItem.Builder(item).setRemoveAudio(muted).build()
        try {
            val exporter = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        busy = false; output = null
                        latestSave(file.copy(path = target.path, name = "video.mp4", size = target.length()))
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        busy = false; target.delete(); output = null
                        failure = "Не удалось сохранить видео. Попробуйте ещё раз."
                    }
                }).build()
            transformer = exporter
            exporter.start(edited, target.path)
        } catch (_: Exception) {
            transformer?.cancel(); busy = false; target.delete(); output = null
            failure = "Не удалось сохранить видео. Попробуйте ещё раз."
        }
    }
    DisposableEffect(player, owner) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY && player.duration > 0) duration = player.duration
            }
            override fun onPlayerError(error: PlaybackException) { failure = "Не удалось открыть видео" }
        }
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) player.pause() }
        owner.lifecycle.addObserver(observer)
        player.addListener(listener)
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(File(file.path))))
        player.prepare()
        onDispose {
            owner.lifecycle.removeObserver(observer)
            player.removeListener(listener); player.release()
            transformer?.cancel(); output?.delete()
        }
    }
    LaunchedEffect(muted) { player.volume = if (muted) 0f else 1f }
    LaunchedEffect(player, start, end) {
        while (true) {
            if (player.isPlaying && end > 0 && player.currentPosition >= end) { player.pause(); player.seekTo(start) }
            delay(40)
        }
    }
    Dialog(onDismissRequest = ::close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val panelHeight = (maxHeight * .48f).coerceAtMost(340.dp)
            Column {
                Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = ::close, enabled = !busy) { Text("Отмена") }
                    Text("Редактор видео", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = ::save, enabled = duration > 0 && end > start && !busy) { Text("Готово") }
                }
                AndroidView(factory = { PlayerView(it).apply { this.player = player; useController = false } },
                    modifier = Modifier.fillMaxWidth().weight(1f).background(Color.Black))
                Column(Modifier.fillMaxWidth().heightIn(max = panelHeight).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    if (busy) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("Сохраняем видео…") }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Обрезка", style = MaterialTheme.typography.titleSmall)
                        Text(videoTime(end - start))
                    }
                    RangeSlider(value = selection, onValueChange = {
                        val minimum = if (duration > 0) minOf(1f, 250f / duration) else 1f
                        if (it.endInclusive - it.start >= minimum) { selection = it; player.pause() }
                    }, onValueChangeFinished = { player.seekTo(start) }, enabled = duration > 0 && !busy)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Начало ${videoTime(start)}"); Text("Конец ${videoTime(end)}")
                    }
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = ::preview, enabled = duration > 0 && !busy) { Text("Смотреть") }
                        Spacer(Modifier.weight(1f))
                        Text("Без звука")
                        Switch(muted, { muted = it }, enabled = !busy)
                    }
                    TextButton(onClick = { selection = 0f..1f; muted = false; player.pause(); player.seekTo(0) }, enabled = changed && !busy) { Text("Сбросить") }
                }
            }
            }
            if (confirmClose) AlertDialog(onDismissRequest = { confirmClose = false },
                title = { Text("Выйти без сохранения?") },
                confirmButton = { TextButton(onClick = onClose) { Text("Выйти") } },
                dismissButton = { TextButton(onClick = { confirmClose = false }) { Text("Продолжить") } })
        }
    }
}

private fun videoTime(ms: Long): String {
    val value = ms.coerceAtLeast(0)
    return "%d:%02d.%d".format(value / 60000, value / 1000 % 60, value / 100 % 10)
}
