package app.maxly.ui.chat

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import io.github.alexzhirkevich.compottie.Compottie
import io.github.alexzhirkevich.compottie.Lottie
import io.github.alexzhirkevich.compottie.LottieCompositionSpec
import io.github.alexzhirkevich.compottie.rememberLottieComposition
import io.github.alexzhirkevich.compottie.rememberLottiePainter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Lottie по адресу, иначе неподвижная картинка. JSON качается один раз и кэшируется.
 * Анимодзи внутри обычного текста сюда не попадают: играет только отдельное сообщение.
 */
@Composable
fun LottieOrStill(lottieUrl: String?, stillUrl: String?, modifier: Modifier = Modifier, description: String) {
    val json = lottieUrl?.takeIf { it.isNotBlank() }?.let { rememberLottieJson(it) }
    Box(modifier) {
        if (!stillUrl.isNullOrBlank()) {
            AsyncImage(stillUrl, description, Modifier.matchParentSize(), contentScale = ContentScale.Fit)
        }
        if (json != null) LottieJson(json, description, Modifier.matchParentSize())
    }
}

/** Отдельный вызов: `remember` появляется вместе с JSON и больше не меняет число слотов. */
@Composable
private fun LottieJson(json: String, description: String, modifier: Modifier) {
    val composition by rememberLottieComposition(LottieCompositionSpec.JsonString(json))
    val painter = rememberLottiePainter(
        composition = composition,
        iterations = Compottie.IterateForever,
    )
    if (composition == null) return
    Lottie(
        painter = painter,
        contentDescription = description,
        modifier = modifier,
        contentScale = ContentScale.Fit,
    )
}

private val lottieJson = java.util.concurrent.ConcurrentHashMap<String, String>()
private val lottieHttp by lazy { OkHttpClient() }

@Composable
private fun rememberLottieJson(url: String): String? {
    var json by remember(url) { mutableStateOf(lottieJson[url]) }
    LaunchedEffect(url) {
        if (json != null) return@LaunchedEffect
        val loaded = withContext(Dispatchers.IO) {
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
        if (loaded != null) {
            lottieJson[url] = loaded
            json = loaded
        }
    }
    return json
}
