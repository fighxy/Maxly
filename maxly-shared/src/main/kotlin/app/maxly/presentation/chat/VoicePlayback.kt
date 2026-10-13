package app.maxly.presentation.chat

import kotlinx.coroutines.flow.StateFlow

/** Чьё голосовое играет: для полосы над чатом и списком чатов. */
data class VoiceMeta(
    val chatId: String = "",
    /** Автор голосового; пусто — «Голосовое сообщение». */
    val author: String = "",
    /** Время сообщения: чат открывается на нём без отдельного запроса. */
    val sentAtMs: Long = 0,
)

/** Что сейчас играет: голосовое [voiceId] сообщения [messageId]. */
data class VoicePlayback(
    val messageId: String,
    val voiceId: String,
    val isPlaying: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    /** Файл ещё грузится. */
    val isBuffering: Boolean = false,
    val meta: VoiceMeta = VoiceMeta(),
    /** Скорость: 1, 1.5 или 2 ([VoiceSpeed]). Голос не искажается. */
    val speed: Float = 1f,
) {
    /** Доля прослушанного 0…1. */
    val progress: Float
        get() = if (durationMs <= 0) 0f else (positionMs.toFloat() / durationMs).coerceIn(0f, 1f)

    fun matches(messageId: String, voiceId: String) = this.messageId == messageId && this.voiceId == voiceId

    /** Подпись полосы: автор или «Голосовое сообщение». */
    val title: String get() = meta.author.ifBlank { "Голосовое сообщение" }
}

/** Ускорение голосовых, как в популярных мессенджерах: 1x → 1.5x → 2x → 1x. */
object VoiceSpeed {
    val steps = listOf(1f, 1.5f, 2f)

    fun next(speed: Float): Float = steps.firstOrNull { it > speed + 0.01f } ?: steps.first()

    fun label(speed: Float): String = when {
        speed >= 1.99f -> "2x"
        speed >= 1.49f -> "1.5x"
        else -> "1x"
    }
}

/** Проигрыватель голосовых: одно голосовое за раз на всё приложение. */
interface VoicePlayer {
    val playback: StateFlow<VoicePlayback?>

    /** Начать с доли [from] (0…1) или продолжить с паузы. */
    fun play(messageId: String, voiceId: String, url: String, durationMs: Long, from: Float? = null, meta: VoiceMeta = VoiceMeta())

    fun pause()

    /** Продолжить голосовое на паузе (полоса над чатом и списком). */
    fun resume()

    /** Перемотать играющее голосовое на долю 0…1. */
    fun seek(fraction: Float)

    /** Скорость для этого и следующих голосовых; высота голоса не меняется. */
    fun setSpeed(speed: Float)

    fun stop()
}
