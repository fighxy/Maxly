package app.orbitle.presentation.chat

import kotlinx.coroutines.flow.StateFlow

/** Что сейчас играет: голосовое [voiceId] сообщения [messageId]. */
data class VoicePlayback(
    val messageId: String,
    val voiceId: String,
    val isPlaying: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    /** Файл ещё грузится. */
    val isBuffering: Boolean = false,
) {
    /** Доля прослушанного 0…1. */
    val progress: Float
        get() = if (durationMs <= 0) 0f else (positionMs.toFloat() / durationMs).coerceIn(0f, 1f)

    fun matches(messageId: String, voiceId: String) = this.messageId == messageId && this.voiceId == voiceId
}

/** Проигрыватель голосовых: одно голосовое за раз на всё приложение. */
interface VoicePlayer {
    val playback: StateFlow<VoicePlayback?>

    /** Начать с доли [from] (0…1) или продолжить с паузы. */
    fun play(messageId: String, voiceId: String, url: String, durationMs: Long, from: Float? = null)

    fun pause()

    /** Перемотать играющее голосовое на долю 0…1. */
    fun seek(fraction: Float)

    fun stop()
}
