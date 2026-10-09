package app.maxly.ui.settings

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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.SwingPanel
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.domain.MiniApp
import app.maxly.platform.AppPaths
import app.maxly.platform.BackHandler
import app.maxly.platform.DesktopActions
import app.maxly.presentation.settings.MiniAppBridge
import app.maxly.presentation.settings.MiniAppVault
import app.maxly.presentation.settings.MiniAppViewModel
import dev.datlag.kcef.KCEF
import dev.datlag.kcef.KCEFBrowser
import dev.datlag.kcef.KCEFClient
import java.awt.BorderLayout
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import java.io.File
import java.util.concurrent.TimeUnit
import javax.swing.JComponent
import javax.swing.JPanel
import javax.swing.SwingUtilities
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import org.cef.browser.CefBrowser
import org.cef.browser.CefFrame
import org.cef.browser.CefMessageRouter
import org.cef.browser.CefRendering
import org.cef.callback.CefQueryCallback
import org.cef.handler.CefLifeSpanHandlerAdapter
import org.cef.handler.CefLoadHandlerAdapter
import org.cef.handler.CefMessageRouterHandlerAdapter
import org.cef.handler.CefRequestHandlerAdapter
import org.cef.network.CefRequest

/**
 * Лист мини-приложения. Страница открывается во встроенном Chromium:
 * системный браузер потерял бы возврат с Госуслуг (`externalCallback=1`).
 * Движок скачивается один раз в каталог профиля, не при каждом запуске приложения.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MiniAppScreen(model: MiniAppViewModel, onClose: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    var confirmClose by remember { mutableStateOf(false) }
    val page = remember { MiniAppPage() }
    LaunchedEffect(Unit) {
        if (model.state.value.phase is MiniAppViewModel.Phase.Loading) model.launch()
        DesktopWebRuntime.ensure()
    }
    fun requestClose() {
        if (model.state.value.closingNeedsConfirmation) confirmClose = true else onClose()
    }
    BackHandler {
        if (confirmClose) confirmClose = false else requestClose()
    }
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
            is MiniAppViewModel.Phase.Failed -> FailedPane(phase.message, Modifier.padding(padding).fillMaxSize(), model::launch)
            is MiniAppViewModel.Phase.Ready -> Box(Modifier.padding(padding).fillMaxSize()) {
                RuntimeGate {
                    MiniAppHost(phase.app, page, model, onClose = ::requestClose)
                }
            }
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

@Composable
private fun FailedPane(message: String, modifier: Modifier, onRetry: () -> Unit) {
    Column(modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text("Не удалось открыть", style = MaterialTheme.typography.titleMedium)
        Text(message, modifier = Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onRetry, modifier = Modifier.padding(top = 16.dp)) { Text("Повторить") }
    }
}

@Composable
private fun RuntimeGate(content: @Composable () -> Unit) {
    val ready by DesktopWebRuntime.ready.collectAsStateWithLifecycle()
    val progress by DesktopWebRuntime.progress.collectAsStateWithLifecycle()
    val failed by DesktopWebRuntime.failed.collectAsStateWithLifecycle()
    val restart by DesktopWebRuntime.restart.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    when {
        restart -> Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Text("Перезапустите Maxly, чтобы открыть мини-приложение.")
        }
        failed != null -> FailedPane(failed ?: "Не удалось подготовить браузер", Modifier.fillMaxSize()) {
            scope.launch { DesktopWebRuntime.ensure() }
        }
        !ready -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                val percent = progress?.toInt()
                Text(
                    if (percent == null || percent <= 0) "Подготовка браузера…" else "Загрузка браузера $percent%",
                    modifier = Modifier.padding(top = 12.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        else -> content()
    }
}

@Composable
private fun MiniAppHost(app: MiniApp, page: MiniAppPage, model: MiniAppViewModel, onClose: () -> Unit) {
    val vault = remember { MiniAppVault.file(File(AppPaths.home, "mini-app-vault.json")) }
    val bridge = remember(app.botId, app.deviceId) {
        MiniAppBridge(botId = app.botId, deviceId = app.deviceId, vault = vault)
    }
    var share by remember { mutableStateOf<Pair<String, String?>?>(null) }
    val session = remember(app.url) {
        runCatching { MiniAppSession(app.url, mobileUserAgent = model.kind == MiniApp.Kind.DIGITAL_ID) }.getOrNull()
    }
    if (session == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Не удалось открыть страницу")
        }
        return
    }
    fun deliver(action: MiniAppBridge.Action) {
        val reply = action as? MiniAppBridge.Action.Reply ?: return
        session.browser.executeJavaScript(bridge.deliverCall(reply.event, reply.json), "", 0)
    }
    fun handle(name: String, json: String?) {
        val width = session.component.width.takeIf { it > 0 } ?: 960
        val height = session.component.height.takeIf { it > 0 } ?: 720
        for (action in bridge.handle(name, json, width, height)) {
            when (action) {
                MiniAppBridge.Action.Ready, MiniAppBridge.Action.Ignore, is MiniAppBridge.Action.Haptic -> Unit
                MiniAppBridge.Action.Close -> onClose()
                is MiniAppBridge.Action.BackButton -> model.showBackButton(action.visible)
                is MiniAppBridge.Action.ClosingConfirmation -> model.setClosingConfirmation(action.needed)
                is MiniAppBridge.Action.OpenLink -> DesktopActions.open(action.url)
                is MiniAppBridge.Action.Share -> share = action.text to action.requestId
                is MiniAppBridge.Action.Reply -> session.browser.executeJavaScript(bridge.deliverCall(action.event, action.json), "", 0)
            }
        }
    }
    DisposableEffect(session) {
        session.listener = object : MiniAppSession.Listener {
            override fun onEvent(name: String, json: String?) = handle(name, json)
            override fun onExternalCallback(url: String) = model.handleCallback(url)
            override fun onOpenExternal(url: String) = DesktopActions.open(url)
        }
        page.pressBack = { deliver(bridge.backPressed) }
        onDispose {
            page.pressBack = {}
            session.listener = null
            session.close()
        }
    }
    // Белый фон панели: прозрачная дырка Compose на Windows остаётся чёрной, пока Chromium не нарисовал кадр.
    SwingPanel(
        factory = {
            session.component.apply { background = java.awt.Color.WHITE }
        },
        modifier = Modifier.fillMaxSize(),
        update = { session.refit() },
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
                    DesktopActions.copy(pending.first)
                    deliver(bridge.shareFinished(pending.second, completed = true))
                    share = null
                }) { Text("Копировать") }
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

/**
 * Один браузер мини-приложения. Клиент закрывается вместе с листом,
 * сам движок остаётся: следующее открытие не качает его заново.
 * Каталог кэша общий, поэтому куки Госуслуг переживают перезапуск страницы.
 */
/** UA системного WebView на том же профиле, что сеанс: Android 14, Pixel 8. */
private const val DIGITAL_ID_USER_AGENT =
    "Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/124.0.0.0 Mobile Safari/537.36"

private class MiniAppSession(url: String, mobileUserAgent: Boolean) {
    interface Listener {
        fun onEvent(name: String, json: String?)
        fun onExternalCallback(url: String)
        fun onOpenExternal(url: String)
    }

    var listener: Listener? = null
    val client: KCEFClient = KCEF.newClientOrNullBlocking() ?: error("Браузер не готов")
    private val router: CefMessageRouter = CefMessageRouter.create(
        CefMessageRouter.CefMessageRouterConfig("cefQuery", "cefQueryCancel"),
    )
    lateinit var browser: KCEFBrowser
    val component: JComponent
    private val closed = AtomicBoolean(false)
    private val armed = AtomicBoolean(false)
    private val pageUrl = url
    private val wantsMobileUserAgent = mobileUserAgent

    init {
        router.addHandler(object : CefMessageRouterHandlerAdapter() {
            override fun onQuery(
                browser: CefBrowser?,
                frame: CefFrame?,
                queryId: Long,
                request: String?,
                persistent: Boolean,
                callback: CefQueryCallback?,
            ): Boolean {
                callback?.success("")
                if (request != null) SwingUtilities.invokeLater { deliverQuery(request) }
                return true
            }
        }, true)
        client.addMessageRouter(router)
        client.addRequestHandler(object : CefRequestHandlerAdapter() {
            override fun onBeforeBrowse(
                browser: CefBrowser?,
                frame: CefFrame?,
                request: CefRequest?,
                userGesture: Boolean,
                isRedirect: Boolean,
            ): Boolean = consume(request?.url)

            override fun onOpenURLFromTab(browser: CefBrowser?, frame: CefFrame?, targetUrl: String?, userGesture: Boolean): Boolean {
                if (!targetUrl.isNullOrBlank() && !consume(targetUrl)) {
                    SwingUtilities.invokeLater { load(targetUrl) }
                }
                return true
            }
        })
        client.addLoadHandler(object : CefLoadHandlerAdapter() {
            override fun onLoadStart(browser: CefBrowser?, frame: CefFrame?, transitionType: CefRequest.TransitionType?) {
                frame?.executeJavaScript(MiniAppBridge.userScript(MiniAppBridge.DESKTOP_POST), "", 0)
            }
        })
        client.addLifeSpanHandler(object : CefLifeSpanHandlerAdapter() {
            override fun onBeforePopup(browser: CefBrowser?, frame: CefFrame?, targetUrl: String?, targetFrameName: String?): Boolean {
                if (!targetUrl.isNullOrBlank() && !consume(targetUrl)) {
                    SwingUtilities.invokeLater { load(targetUrl) }
                }
                return true
            }
        })
        // Пустая страница, пока панель не получит размер и DevTools не поставит скрипт до документа.
        // Окно Chromium, созданное в 0×0, на Windows так и остаётся чёрным прямоугольником.
        // bridge.js выбирает транспорт один раз: если WebViewHandler появится позже, события теряются.
        browser = client.createBrowser("about:blank", CefRendering.DEFAULT, false)
        val ui = browser.uiComponent ?: error("Страница не создалась")
        if (ui is JComponent) {
            ui.isOpaque = true
            ui.background = java.awt.Color.WHITE
        }
        component = JPanel(BorderLayout()).apply {
            background = java.awt.Color.WHITE
            isOpaque = true
            add(ui, BorderLayout.CENTER)
            addComponentListener(object : ComponentAdapter() {
                override fun componentShown(e: ComponentEvent) = fit()
                override fun componentResized(e: ComponentEvent) = fit()
            })
        }
    }

    /**
     * Compose ставит размер панели после первого кадра. Пока ширина нулевая,
     * нативный вид Chromium не к чему привязать, и вместо страницы остаётся чёрное поле.
     */
    private var fitting = false

    private fun fit() {
        if (closed.get() || fitting) return
        val width = component.width
        val height = component.height
        if (width <= 1 || height <= 1) return
        val ui = browser.uiComponent ?: return
        fitting = true
        try {
            ui.setBounds(0, 0, width, height)
            runCatching { component.validate() }
            runCatching { browser.createImmediately() }
            runCatching { browser.wasResized(width, height) }
            runCatching { browser.notifyScreenInfoChanged() }
            if (armed.compareAndSet(false, true)) arm(pageUrl, wantsMobileUserAgent)
        } finally {
            fitting = false
        }
    }

    /** Повторная примерка после того, как Compose поставил границы панели. */
    fun refit() = fit()

    /**
     * Скрипт на старте каждого документа и, для Цифрового ID, UA настоящего WebView.
     * Антифрод Госуслуг и страница id отбрасывают и UA ядра `OKMessages`, и десктопный Chrome.
     * Если DevTools не ответил, адрес всё равно открывается: запасной ввод остаётся в `onLoadStart`.
     */
    private fun arm(url: String, mobileUserAgent: Boolean) {
        val opened = AtomicBoolean(false)
        fun open() {
            if (closed.get() || !opened.compareAndSet(false, true)) return
            val load = Runnable {
                if (!closed.get()) {
                    browser.setWindowVisibility(true)
                    browser.loadURL(url)
                }
            }
            if (SwingUtilities.isEventDispatchThread()) load.run() else SwingUtilities.invokeLater(load)
        }
        // DevTools на потоке окна может не отпустить кадр: страница так и остаётся about:blank.
        javax.swing.Timer(2_000) { open() }.apply { isRepeats = false; start() }
        Thread({
            val dev = runCatching { browser.devToolsClient }.getOrNull()
            if (dev == null) {
                open()
                return@Thread
            }
            if (mobileUserAgent) {
                val userAgent = runCatching {
                    dev.executeDevToolsMethod(
                        "Emulation.setUserAgentOverride",
                        """{"userAgent":${Json.encodeToString(DIGITAL_ID_USER_AGENT)},"platform":"Linux armv8l"}""",
                    ).get(1_500, TimeUnit.MILLISECONDS)
                }
                if (userAgent.isFailure) {
                    open()
                    return@Thread
                }
            }
            runCatching {
                dev.executeDevToolsMethod(
                    "Page.addScriptToEvaluateOnNewDocument",
                    """{"source":${Json.encodeToString(MiniAppBridge.userScript(MiniAppBridge.DESKTOP_POST))}}""",
                ).get(1_500, TimeUnit.MILLISECONDS)
            }
            open()
        }, "maxly-mini-app").apply { isDaemon = true }.start()
    }

    fun close() {
        closed.set(true)
        listener = null
        runCatching { client.removeMessageRouter(router) }
        runCatching { browser.dispose() }
        runCatching { client.dispose() }
    }

    private fun load(url: String) {
        if (this::browser.isInitialized) browser.loadURL(url)
    }

    /** `true` — переход забран у страницы. Решение синхронное, действие уходит на поток окна. */
    private fun consume(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        if (MiniApp.isExternalCallback(url)) {
            SwingUtilities.invokeLater { listener?.onExternalCallback(url) }
            return true
        }
        if (MiniApp.opensExternally(url)) {
            SwingUtilities.invokeLater { listener?.onOpenExternal(url) }
            return true
        }
        return false
    }

    private fun deliverQuery(raw: String) {
        val obj = try {
            Json.parseToJsonElement(raw) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return
        val name = (obj["name"] as? JsonPrimitive)?.contentOrNull ?: return
        val data = (obj["data"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }
        listener?.onEvent(name, data)
    }
}

/** Движок страницы. Инициализация при первом мини-приложении, не при старте клиента. */
private object DesktopWebRuntime {
    private val gate = Mutex()
    val ready = MutableStateFlow(false)
    val progress = MutableStateFlow<Float?>(null)
    val failed = MutableStateFlow<String?>(null)
    val restart = MutableStateFlow(false)

    suspend fun ensure() {
        if (ready.value || restart.value) return
        gate.withLock {
            if (ready.value || restart.value) return
            failed.value = null
            val bundle = File(AppPaths.home, "kcef-bundle")
            val cache = File(AppPaths.home, "cef-cache")
            bundle.mkdirs()
            cache.mkdirs()
            try {
                withContext(Dispatchers.IO) {
                    KCEF.init(
                        builder = {
                            installDir(bundle)
                            settings {
                                cachePath = cache.absolutePath
                                persistSessionCookies = true
                                // Непрозрачный фон ускоренного слоя. Ноль в альфе оставляет чёрный кадр.
                                backgroundColor = org.cef.CefSettings().run { ColorType(255, 255, 255, 255) }
                            }
                            progress {
                                onDownloading { value -> progress.value = value.coerceAtLeast(0f) }
                                onInitialized { ready.value = true }
                            }
                        },
                        onError = { error ->
                            if (!ready.value) failed.value = error?.message ?: "Не удалось подготовить браузер"
                        },
                        onRestartRequired = { restart.value = true },
                    )
                }
                if (!restart.value && failed.value == null) ready.value = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (!ready.value) failed.value = e.message ?: "Не удалось подготовить браузер"
            }
        }
    }
}
