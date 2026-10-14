package app.maxly.ui.chat

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import io.github.alexzhirkevich.compottie.Compottie
import io.github.alexzhirkevich.compottie.Lottie
import io.github.alexzhirkevich.compottie.animateLottieCompositionAsState
import io.github.alexzhirkevich.compottie.LottieCompositionSpec
import io.github.alexzhirkevich.compottie.rememberLottieComposition
import io.github.alexzhirkevich.compottie.rememberLottiePainter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Lottie по адресу, иначе неподвижная картинка. JSON качается один раз и кэшируется.
 * [iterations] — сколько раз проиграть (по умолчанию без конца); [fallback] виден, пока
 * анимация не загрузилась (эмодзи буквой).
 */
@Composable
fun LottieOrStill(
    lottieUrl: String?,
    stillUrl: String?,
    modifier: Modifier = Modifier,
    description: String,
    iterations: Int = Compottie.IterateForever,
    fallback: (@Composable () -> Unit)? = null,
) {
    val json = lottieUrl?.takeIf { it.isNotBlank() }?.let { rememberLottieJson(it) }
    Box(modifier, contentAlignment = androidx.compose.ui.Alignment.Center) {
        if (!stillUrl.isNullOrBlank()) {
            AsyncImage(stillUrl, description, Modifier.matchParentSize(), contentScale = ContentScale.Fit)
        }
        if (json != null) {
            LottieJson(json, description, Modifier.matchParentSize(), iterations)
        } else if (stillUrl.isNullOrBlank()) {
            fallback?.invoke()
        }
    }
}

/** Отдельный вызов: `remember` появляется вместе с JSON и больше не меняет число слотов. */
@Composable
private fun LottieJson(json: String, description: String, modifier: Modifier, iterations: Int) {
    val composition by rememberLottieComposition(LottieCompositionSpec.JsonString(json))
    val painter = rememberLottiePainter(
        composition = composition,
        iterations = iterations,
    )
    if (composition == null) return
    Lottie(
        painter = painter,
        contentDescription = description,
        modifier = modifier,
        contentScale = ContentScale.Fit,
    )
}

/**
 * Lottie [lottieUrl] один проход, затем [onEnd]. Пока JSON качается, виден [fallback]; если
 * анимация не загрузилась, [onEnd] зовёт тот, кто её показал (по своему сроку).
 */
@Composable
fun LottieOnce(lottieUrl: String, modifier: Modifier = Modifier, description: String, fallback: (@Composable () -> Unit)? = null, onEnd: () -> Unit) {
    val json = rememberLottieJson(lottieUrl)
    Box(modifier, contentAlignment = androidx.compose.ui.Alignment.Center) {
        if (json != null) LottieJsonOnce(json, description, Modifier.matchParentSize(), onEnd) else fallback?.invoke()
    }
}

@Composable
private fun LottieJsonOnce(json: String, description: String, modifier: Modifier, onEnd: () -> Unit) {
    val composition by rememberLottieComposition(LottieCompositionSpec.JsonString(json))
    val animation = animateLottieCompositionAsState(composition, iterations = 1)
    val painter = rememberLottiePainter(composition = composition, progress = { animation.value })
    val end by rememberUpdatedState(onEnd)
    LaunchedEffect(composition) {
        if (composition == null) return@LaunchedEffect
        snapshotFlow { animation.isAtEnd && !animation.isPlaying }.first { it }
        end()
    }
    if (composition == null) return
    Lottie(painter = painter, contentDescription = description, modifier = modifier, contentScale = ContentScale.Fit)
}

/** Заранее скачать JSON анимаций [urls] (реакции): по нажатию они играют сразу. */
suspend fun prefetchLottie(urls: Collection<String>) {
    urls.filter { it.isNotBlank() && !lottieJson.containsKey(it) }.forEach { url -> loadLottieJson(url)?.let { lottieJson[url] = it } }
}

private val lottieJson = java.util.concurrent.ConcurrentHashMap<String, String>()
private val lottieHttp by lazy { OkHttpClient() }

private suspend fun loadLottieJson(url: String): String? = withContext(Dispatchers.IO) {
    try {
        lottieHttp.newCall(Request.Builder().url(url).build()).execute().use { response ->
            val body = response.body?.string()
            body?.takeIf { response.isSuccessful && it.trimStart().startsWith("{") }
        }
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }
}

@Composable
private fun rememberLottieJson(url: String): String? {
    var json by remember(url) { mutableStateOf(lottieJson[url]) }
    LaunchedEffect(url) {
        if (json != null) return@LaunchedEffect
        val loaded = loadLottieJson(url)
        if (loaded != null) {
            lottieJson[url] = loaded
            json = loaded
        }
    }
    return json
}
