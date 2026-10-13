package app.maxly.ui.chat

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import app.maxly.presentation.chat.AnimojiText
import app.maxly.presentation.chat.ReactionBurst
import kotlinx.coroutines.delay

/** Анимодзи чата: эмодзи → Lottie ([app.maxly.presentation.chat.ChatUiState.animoji]). */
val LocalAnimoji = compositionLocalOf<Map<String, String>> { emptyMap() }

/** Только что поставленная реакция и отметка «доиграла». */
class ReactionBurstHost(val burst: ReactionBurst?, val onShown: (Long) -> Unit)

val LocalReactionBurst = compositionLocalOf { ReactionBurstHost(null) {} }

/**
 * Метка встроенного содержимого Compose (`appendInlineContent` ставит такую же): ею эмодзи в
 * тексте отмечается на своём месте, без сдвига остальной разметки.
 */
private const val INLINE_CONTENT_TAG = "androidx.compose.foundation.text.inlineContent"

private fun inlineId(url: String) = "animoji:$url"

/** Отметить анимодзи [placed] в тексте [builder]: на их месте будет Lottie ([animojiInlineContent]). */
fun markAnimoji(builder: AnnotatedString.Builder, placed: List<AnimojiText.Placed>) {
    placed.forEach { builder.addStringAnnotation(INLINE_CONTENT_TAG, inlineId(it.lottieUrl), it.from, it.from + it.length) }
}

/** Lottie для отмеченных анимодзи: квадрат чуть больше буквы, по центру строки. */
fun animojiInlineContent(placed: List<AnimojiText.Placed>): Map<String, InlineTextContent> =
    placed.distinctBy { it.lottieUrl }.associate { item ->
        inlineId(item.lottieUrl) to InlineTextContent(Placeholder(1.25.em, 1.25.em, PlaceholderVerticalAlign.TextCenter)) {
            LottieOrStill(item.lottieUrl, null, Modifier.fillMaxSize(), item.emoji) { Text(item.emoji) }
        }
    }

/**
 * Анимация реакции, которую пользователь только что поставил на сообщение [messageId]: один
 * проход Lottie над пузырём, затем [ReactionBurstHost.onShown].
 */
@Composable
fun ReactionBurstOverlay(messageId: String, modifier: Modifier = Modifier) {
    val host = LocalReactionBurst.current
    val burst = host.burst?.takeIf { it.messageId == messageId } ?: return
    key(burst.id) {
        LaunchedEffect(burst.id) {
            delay(BURST_MS)
            host.onShown(burst.id)
        }
        LottieOrStill(burst.lottieUrl, null, modifier.padding(horizontal = 16.dp).size(120.dp), burst.emoji, iterations = 1)
    }
}

private const val BURST_MS = 2_200L
