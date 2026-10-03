package app.orbitle.ui.settings

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Message
import android.view.HapticFeedbackConstants
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.orbitle.domain.MiniApp
import app.orbitle.presentation.settings.MiniAppBridge
import app.orbitle.presentation.settings.MiniAppViewModel

/**
 * Лист мини-приложения: страница внутри приложения, чтобы возврат с Госуслуг
 * (`externalCallback=1`) остался в клиенте, а не в системном браузере.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MiniAppScreen(model: MiniAppViewModel, onClose: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    var confirmClose by remember { mutableStateOf(false) }
    val page = remember { MiniAppPage() }
    LaunchedEffect(Unit) {
        if (model.state.value.phase is MiniAppViewModel.Phase.Loading) model.launch()
    }
    fun requestClose() {
        if (model.state.value.closingNeedsConfirmation) confirmClose = true else onClose()
    }
    androidx.activity.compose.BackHandler { requestClose() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(model.title) },
                navigationIcon = {
                    if (state.showsBackButton) {
                        IconButton(onClick = { page.pressBack() }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад")
                        }
                    }
                },
                actions = { TextButton(onClick = ::requestClose) { Text("Закрыть") } },
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        when (val phase = state.phase) {
            MiniAppViewModel.Phase.Loading -> Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is MiniAppViewModel.Phase.Failed -> Column(
                Modifier.padding(padding).fillMaxSize().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("Не удалось открыть", style = MaterialTheme.typography.titleMedium)
                Text(phase.message, modifier = Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = model::launch, modifier = Modifier.padding(top = 16.dp)) { Text("Повторить") }
            }
            is MiniAppViewModel.Phase.Ready -> MiniAppWeb(
                phase.app,
                page,
                model,
                onClose = ::requestClose,
                modifier = Modifier.padding(padding).fillMaxSize(),
            )
        }
    }
    if (confirmClose) {
        AlertDialog(
            onDismissRequest = { confirmClose = false },
            title = { Text("Закрыть «${model.title}»?") },
            text = { Text("Несохранённые данные могут пропасть.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmClose = false
                    onClose()
                }) { Text("Закрыть") }
            },
            dismissButton = { TextButton(onClick = { confirmClose = false }) { Text("Отмена") } },
        )
    }
}

/** Связь панели с открытой страницей: «Назад» уходит в мост. */
class MiniAppPage {
    var pressBack: () -> Unit = {}
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun MiniAppWeb(
    app: MiniApp,
    page: MiniAppPage,
    model: MiniAppViewModel,
    onClose: () -> Unit,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val bridge = remember { MiniAppBridge() }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var share by remember { mutableStateOf<Pair<String, String?>?>(null) }
    fun deliver(action: MiniAppBridge.Action) {
        val reply = action as? MiniAppBridge.Action.Reply ?: return
        webView?.evaluateJavascript(bridge.deliverCall(reply.event, reply.json), null)
    }
    fun handle(view: WebView, name: String, json: String?) {
        val width = view.width.coerceAtLeast(1)
        val height = view.height.coerceAtLeast(1)
        for (action in bridge.handle(name, json, width, height)) {
            when (action) {
                MiniAppBridge.Action.Ready, MiniAppBridge.Action.Ignore -> Unit
                MiniAppBridge.Action.Close -> onClose()
                is MiniAppBridge.Action.BackButton -> model.showBackButton(action.visible)
                is MiniAppBridge.Action.ClosingConfirmation -> model.setClosingConfirmation(action.needed)
                is MiniAppBridge.Action.OpenLink -> openExternal(context, action.url)
                is MiniAppBridge.Action.Haptic -> playHaptic(view, action.kind)
                is MiniAppBridge.Action.Share -> share = action.text to action.requestId
                is MiniAppBridge.Action.Reply -> view.evaluateJavascript(bridge.deliverCall(action.event, action.json), null)
            }
        }
    }
    // Переход с Госуслуг нельзя грузить: сервер выдаёт новый запуск. Откладываем,
    // чтобы не уничтожать WebView внутри его же обратного вызова.
    fun consume(view: WebView, url: String): Boolean {
        if (MiniApp.isExternalCallback(url)) {
            view.post { model.handleCallback(url) }
            return true
        }
        if (MiniApp.opensExternally(url)) {
            view.post { openExternal(context, url) }
            return true
        }
        return false
    }
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            WebView(ctx).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mediaPlaybackRequiresUserGesture = false
                settings.setSupportMultipleWindows(true)
                settings.javaScriptCanOpenWindowsAutomatically = true
                val cookies = CookieManager.getInstance()
                cookies.setAcceptCookie(true)
                cookies.setAcceptThirdPartyCookies(this, true)
                val script = MiniAppBridge.userScript(MiniAppBridge.ANDROID_POST)
                if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                    WebViewCompat.addDocumentStartJavaScript(this, script, setOf("*"))
                }
                addJavascriptInterface(object {
                    @JavascriptInterface
                    fun postEvent(name: String, data: String?) {
                        post { handle(this@apply, name, data?.takeIf { it.isNotEmpty() }) }
                    }
                }, "OrbitleWebApp")
                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                            view.evaluateJavascript(script, null)
                        }
                    }

                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        val url = request.url?.toString().orEmpty()
                        return url.isNotEmpty() && consume(view, url)
                    }
                }
                webChromeClient = object : WebChromeClient() {
                    override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                        val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
                        val popup = WebView(view.context)
                        popup.webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(popupView: WebView, request: WebResourceRequest): Boolean {
                                val target = request.url?.toString().orEmpty()
                                view.post {
                                    if (target.isNotEmpty() && !consume(view, target)) view.loadUrl(target)
                                    popupView.destroy()
                                }
                                return true
                            }
                        }
                        transport.webView = popup
                        resultMsg.sendToTarget()
                        return true
                    }
                }
                tag = app.url
                loadUrl(app.url)
                webView = this
                page.pressBack = { deliver(bridge.backPressed) }
            }
        },
        update = { view ->
            webView = view
            page.pressBack = { deliver(bridge.backPressed) }
            if (view.tag != app.url) {
                view.tag = app.url
                view.loadUrl(app.url)
            }
        },
        onRelease = { view ->
            page.pressBack = {}
            view.removeJavascriptInterface("OrbitleWebApp")
            view.destroy()
        },
    )
    val pending = share
    if (pending != null) {
        AlertDialog(
            onDismissRequest = {
                deliver(bridge.shareFinished(pending.second, completed = false))
                share = null
            },
            title = { Text("Поделиться") },
            text = { Text(pending.first) },
            confirmButton = {
                TextButton(onClick = {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, pending.first)
                    }
                    val started = try {
                        context.startActivity(Intent.createChooser(send, "Поделиться"))
                        true
                    } catch (_: ActivityNotFoundException) {
                        false
                    }
                    deliver(bridge.shareFinished(pending.second, completed = started))
                    share = null
                }) { Text("Отправить") }
            },
            dismissButton = {
                TextButton(onClick = {
                    deliver(bridge.shareFinished(pending.second, completed = false))
                    share = null
                }) { Text("Отмена") }
            },
        )
    }
}

private fun openExternal(context: android.content.Context, url: String) {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
    }
}

private fun playHaptic(view: View, kind: MiniAppBridge.HapticKind) {
    val constant = when (kind) {
        is MiniAppBridge.HapticKind.Impact -> when (kind.style) {
            "heavy" -> HapticFeedbackConstants.LONG_PRESS
            "medium" -> HapticFeedbackConstants.KEYBOARD_TAP
            else -> HapticFeedbackConstants.VIRTUAL_KEY
        }
        is MiniAppBridge.HapticKind.Notification -> when (kind.type) {
            "error" -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
            "warning" -> HapticFeedbackConstants.LONG_PRESS
            else -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        }
        MiniAppBridge.HapticKind.Selection -> HapticFeedbackConstants.CLOCK_TICK
    }
    view.performHapticFeedback(constant)
}
