package app.maxly.ui.chat

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.maxly.presentation.chat.AnimojiText
import app.maxly.presentation.chat.ReactionBurst
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/** Анимодзи чата: эмодзи → Lottie ([app.maxly.presentation.chat.ChatUiState.animoji]). */
val LocalAnimoji = compositionLocalOf<Map<String, String>> { emptyMap() }

/**
 * Только что поставленная реакция ([app.maxly.presentation.chat.ChatUiState.reactionBurst]): её
 * значок в плашке ([ReactionGlyph]) играет анимацию на месте и сообщает, где он на экране; эффект
 * вокруг рисует [ReactionEffectLayer] поверх ленты, чтобы пузырь его не обрезал. Когда доиграли
 * оба (или вышел срок), [onShown].
 */
@Stable
class ReactionBurstHost(private val onShown: (Long) -> Unit) {
    var burst by mutableStateOf<ReactionBurst?>(null)
        private set
    /** Где значок, в координатах окна. */
    internal var anchor by mutableStateOf<Rect?>(null)
    internal var bodyDone by mutableStateOf(true)
        private set
    internal var effectDone by mutableStateOf(true)
        private set

    internal fun update(next: ReactionBurst?) {
        if (next?.id == burst?.id) return
        burst = next
        anchor = null
        bodyDone = next?.lottieUrl == null
        effectDone = next?.effectUrl == null
    }

    internal fun bodyFinished(id: Long) {
        if (burst?.id != id) return
        bodyDone = true
        finishIfDone(id)
    }

    internal fun effectFinished(id: Long) {
        if (burst?.id != id) return
        effectDone = true
        finishIfDone(id)
    }

    internal fun expire(id: Long) {
        if (burst?.id == id) onShown(id)
    }

    private fun finishIfDone(id: Long) {
        if (bodyDone && effectDone) onShown(id)
    }
}

/** Хозяин анимации реакции экрана чата: следует за [burst] модели. */
@Composable
fun rememberReactionBurst(burst: ReactionBurst?, onShown: (Long) -> Unit): ReactionBurstHost {
    val shown by rememberUpdatedState(onShown)
    val host = remember { ReactionBurstHost { shown(it) } }
    LaunchedEffect(burst?.id) {
        host.update(burst)
        val id = burst?.id ?: return@LaunchedEffect
        // Анимация не загрузилась или значок не на экране — всё равно заканчиваем.
        delay(BURST_LIMIT_MS)
        host.expire(id)
    }
    return host
}

val LocalReactionBurst = compositionLocalOf<ReactionBurstHost?> { null }

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
 * Значок реакции [emoji] в плашке под сообщением [messageId]: эмодзи буквой. Только что
 * поставленная реакция ([LocalReactionBurst]) один раз играет на месте свою анимацию и отмечает,
 * где она на экране, для эффекта вокруг ([ReactionEffectLayer]). Так же, как в Komet.
 */
@Composable
fun ReactionGlyph(messageId: String, emoji: String, fontSize: TextUnit = 15.sp) {
    val host = LocalReactionBurst.current
    val burst = host?.burst?.takeIf { it.matches(messageId, emoji) }
    if (host == null || burst == null) {
        Text(emoji, fontSize = fontSize)
        return
    }
    key(burst.id) {
        val body = burst.lottieUrl?.takeIf { !host.bodyDone }
        // Буква остаётся (невидимой), пока играет анимация: плашка не меняет размер.
        Box(Modifier.onGloballyPositioned { host.anchor = it.boundsInRoot() }, contentAlignment = Alignment.Center) {
            Text(emoji, fontSize = fontSize, modifier = Modifier.alpha(if (body != null) 0f else 1f))
            if (body != null) {
                LottieOnce(body, Modifier.matchParentSize(), emoji, fallback = { Text(emoji, fontSize = fontSize) }) {
                    host.bodyFinished(burst.id)
                }
            }
        }
    }
}

/**
 * Эффект только что поставленной реакции (`lottiePlayUrl`) поверх ленты, по центру её значка:
 * крупный, не обрезается пузырём и едет вместе с лентой. Касаний не перехватывает.
 */
@Composable
fun ReactionEffectLayer(host: ReactionBurstHost, modifier: Modifier = Modifier, size: Dp = EFFECT_SIZE) {
    val burst = host.burst ?: return
    val effect = burst.effectUrl ?: return
    if (host.effectDone) return
    var origin by remember { mutableStateOf(Offset.Zero) }
    Box(modifier.fillMaxSize().onGloballyPositioned { origin = it.positionInRoot() }) {
        val anchor = host.anchor ?: return@Box
        key(burst.id) {
            LottieOnce(
                effect,
                Modifier
                    .offset {
                        val side = size.toPx()
                        IntOffset((anchor.center.x - origin.x - side / 2).roundToInt(), (anchor.center.y - origin.y - side / 2).roundToInt())
                    }
                    .size(size),
                burst.emoji,
            ) { host.effectFinished(burst.id) }
        }
    }
}

/** Заранее скачать анимации и эффекты реакций [emoji] (быстрые реакции): по нажатию они играют сразу. */
@Composable
fun PrefetchReactionAnimations(emoji: List<String>, animoji: Map<String, String>, effects: Map<String, String>) {
    LaunchedEffect(emoji, animoji, effects) {
        prefetchLottie(emoji.flatMap { listOfNotNull(AnimojiText.lookup(animoji, it), AnimojiText.lookup(effects, it)) })
    }
}

/** Эффект реакции — примерно вчетверо больше её значка. */
private val EFFECT_SIZE = 72.dp
private const val BURST_LIMIT_MS = 4_000L
