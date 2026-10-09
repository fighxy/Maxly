package app.maxly.ui.chat

import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import app.maxly.domain.ChatAttachment
import app.maxly.domain.FileContent
import app.maxly.domain.Message
import app.maxly.domain.VoiceContent
import app.maxly.presentation.chat.ChatMediaState
import app.maxly.presentation.chat.VoicePlayback

/**
 * Медиа пузырей: состояние плеера и загрузок плюс действия. Состояния лежат в [State], чтобы
 * частое обновление прогресса перерисовывало только голосовое, а не всю ленту.
 */
class BubbleMedia(
    val playback: State<VoicePlayback?>,
    val media: State<ChatMediaState>,
    val canPlay: (VoiceContent) -> Boolean = { false },
    val canTranscribe: (Message, VoiceContent) -> Boolean = { _, _ -> false },
    val onVoice: (Message, VoiceContent) -> Unit = { _, _ -> },
    val onSeek: (Message, VoiceContent, Float) -> Unit = { _, _, _ -> },
    val onTranscript: (Message, VoiceContent) -> Unit = { _, _ -> },
    val onVisual: (Message, ChatAttachment) -> Unit = { _, _ -> },
    val onFile: (Message, FileContent) -> Unit = { _, _ -> },
    val onRoundEnded: (String) -> Unit = {},
    /** User-Agent для CDN видео. */
    val userAgent: String = "",
) {
    companion object {
        val None = BubbleMedia(mutableStateOf(null), mutableStateOf(ChatMediaState()))
    }
}

val LocalBubbleMedia = compositionLocalOf { BubbleMedia.None }
