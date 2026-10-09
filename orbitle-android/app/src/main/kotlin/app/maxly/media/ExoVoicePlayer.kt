package app.maxly.media

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import app.maxly.presentation.chat.VoicePlayback
import app.maxly.presentation.chat.VoicePlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * [VoicePlayer] на Media3. Плеер создаётся при первом воспроизведении и живёт с приложением;
 * адреса CDN открываются с User-Agent сессии.
 */
@OptIn(UnstableApi::class)
class ExoVoicePlayer(
    private val context: Context,
    private val scope: CoroutineScope,
    private val userAgent: () -> String,
    private val onError: (String) -> Unit = {},
) : VoicePlayer {

    private val _playback = MutableStateFlow<VoicePlayback?>(null)
    override val playback: StateFlow<VoicePlayback?> = _playback.asStateFlow()

    private var player: ExoPlayer? = null
    private var ticker: Job? = null

    private fun player(): ExoPlayer = player ?: ExoPlayer.Builder(context)
        .setMediaSourceFactory(MediaSources.factory(context, userAgent()))
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),
            /* handleAudioFocus = */ true,
        )
        .setHandleAudioBecomingNoisy(true)
        .build()
        .also { created ->
            created.addListener(listener)
            player = created
        }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            sync()
            if (isPlaying) startTicker() else ticker?.cancel()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED) {
                // Дослушали: голосовое возвращается к началу, как в Max.
                _playback.value = null
                player?.run { pause(); clearMediaItems() }
                return
            }
            sync()
        }

        override fun onPlayerError(error: PlaybackException) {
            _playback.value = null
            onError("Не удалось воспроизвести голосовое")
        }
    }

    override fun play(messageId: String, voiceId: String, url: String, durationMs: Long, from: Float?) {
        val exo = player()
        val current = _playback.value
        if (current != null && current.matches(messageId, voiceId)) {
            from?.let { exo.seekTo((it * duration(exo, current.durationMs)).toLong()) }
            exo.play()
            return
        }
        exo.setMediaItem(MediaItem.fromUri(url))
        exo.prepare()
        if (from != null && durationMs > 0) exo.seekTo((from * durationMs).toLong())
        exo.play()
        _playback.value = VoicePlayback(messageId, voiceId, isPlaying = false, positionMs = 0, durationMs = durationMs, isBuffering = true)
    }

    override fun pause() {
        player?.pause()
    }

    override fun seek(fraction: Float) {
        val exo = player ?: return
        val current = _playback.value ?: return
        val target = (fraction.coerceIn(0f, 1f) * duration(exo, current.durationMs)).toLong()
        exo.seekTo(target)
        _playback.update { it?.copy(positionMs = target) }
    }

    override fun stop() {
        player?.run { stop(); clearMediaItems() }
        _playback.value = null
    }

    private fun duration(exo: ExoPlayer, fallback: Long): Long =
        exo.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: fallback

    private fun sync() {
        val exo = player ?: return
        _playback.update { current ->
            current?.copy(
                isPlaying = exo.isPlaying,
                positionMs = exo.currentPosition.coerceAtLeast(0),
                durationMs = duration(exo, current.durationMs),
                isBuffering = exo.playbackState == Player.STATE_BUFFERING,
            )
        }
    }

    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                sync()
                delay(80)
            }
        }
    }
}
