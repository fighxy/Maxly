package app.maxly

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.FrameWindowScope
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPlacement as ComposePlacement
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import app.maxly.data.diagnostics.AppLog
import app.maxly.diagnostics.DesktopDiagnostics
import app.maxly.platform.AppPaths
import app.maxly.platform.DesktopOwner
import app.maxly.platform.WindowBounds
import app.maxly.platform.WindowPlacement
import app.maxly.ui.keys.HotkeyAction
import app.maxly.ui.keys.HotkeyHandler
import app.maxly.ui.res.painterResource
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import com.mohamedrejeb.calf.picker.ProvideFilePickerParentWindow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.swing.Swing
import okio.Path.Companion.toOkioPath
import java.awt.AWTEvent
import java.awt.Dimension
import java.awt.Toolkit
import java.awt.event.AWTEventListener
import java.io.File

fun main() {
    // Журнал — первым: всё, что случится дальше, включая сбой на старте, попадёт в файл.
    DesktopDiagnostics.init(AppPaths.home)
    AppPaths.migration.let {
        if (it.outcome != app.maxly.platform.DataDirMigration.Outcome.NOTHING_TO_DO) {
            AppLog.w("paths", "Каталог данных: ${it.outcome}, ${it.dir}", it.error)
        }
    }
    DesktopDiagnostics.watchUi()
    // Swing-диспетчер становится Dispatchers.Main до первого обращения к сессии.
    Dispatchers.Swing
    SingletonImageLoader.setSafe { context ->
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory()) }
            .diskCache {
                DiskCache.Builder()
                    .directory(File(AppPaths.cacheDir, "image_cache").apply { mkdirs() }.toOkioPath())
                    .build()
            }
            .build()
    }
    application {
        val container = remember { AppContainer() }
        val owner = remember { DesktopOwner() }
        DisposableEffect(owner) {
            owner.moveTo(Lifecycle.State.STARTED)
            onDispose { owner.destroy() }
        }
        // RESUMED — только пока окно видно и в фокусе: открытый чат отмечается прочитанным лишь
        // тогда, а при возврате к окну отмечает последнее видимое сообщение.
        LaunchedEffect(owner, container) {
            container.window.looking.collect { owner.moveTo(DesktopOwner.stateOf(it)) }
        }
        LaunchedEffect(container) { container.session.restoreSession() }
        MainWindow(container, owner, onExit = ::exitApplication)
    }
}

/** Главное окно: открывается там, где его закрыли, и сообщает ядру, смотрит ли в него пользователь. */
@Composable
private fun MainWindow(container: AppContainer, owner: DesktopOwner, onExit: () -> Unit) {
    val start = remember { WindowPlacement.start(container.windowPlacement.load(), WindowPlacement.screens()) }
    val state = rememberWindowState(
        placement = if (start.maximized) ComposePlacement.Maximized else ComposePlacement.Floating,
        position = if (start.x != null && start.y != null) WindowPosition(start.x.dp, start.y.dp) else WindowPosition(Alignment.Center),
        size = DpSize(start.width.dp, start.height.dp),
    )
    Window(
        onCloseRequest = onExit,
        title = "Maxly",
        icon = painterResource(R.drawable.app_icon),
        state = state,
    ) {
        LaunchedEffect(Unit) {
            window.minimumSize = Dimension(WindowPlacement.MIN_WIDTH, WindowPlacement.MIN_HEIGHT)
            AppLog.i("ui", "Окно открыто: ${window.renderApi}, ${state.size}, ${state.placement}")
        }
        RememberPlacement(container, state)
        TrackActivity(container, state)
        RaiseOnIncomingCall(container, state)
        // Ctrl+Q (⌘Q) — выход.
        HotkeyHandler { hotkey ->
            if (hotkey.action == HotkeyAction.QUIT) {
                onExit()
                true
            } else {
                false
            }
        }
        ProvideFilePickerParentWindow {
            CompositionLocalProvider(
                LocalLifecycleOwner provides owner,
                LocalViewModelStoreOwner provides owner,
            ) {
                AppRoot(container)
            }
        }
    }
}

/** Размер и место окна в настройки — через полсекунды после того, как их перестали менять. */
@OptIn(FlowPreview::class)
@Composable
private fun RememberPlacement(container: AppContainer, state: WindowState) {
    LaunchedEffect(state) {
        // Развёрнутое окно хранит прежние размеры: после «Восстановить» оно вернётся к ним.
        var floating = container.windowPlacement.load()
        snapshotFlow { Triple(state.placement, state.position, state.size) }
            .debounce(500)
            .collect { (placement, position, size) ->
                if (state.isMinimized) return@collect
                val maximized = placement != ComposePlacement.Floating
                if (!maximized && position.isSpecified) {
                    floating = WindowBounds(position.x.value.toInt(), position.y.value.toInt(), size.width.value.toInt(), size.height.value.toInt())
                }
                val base = floating ?: return@collect
                container.windowPlacement.save(base.copy(maximized = maximized))
            }
    }
}

/**
 * Свёрнуто ли окно, в фокусе ли оно и был ли ввод: от этого зависят флаг активности для ядра
 * и опрос своего статуса (свёрнутое окно — фон). Без ввода минуту пользователь считается отошедшим.
 */
@Composable
private fun FrameWindowScope.TrackActivity(container: AppContainer, state: WindowState) {
    val windowInfo = LocalWindowInfo.current
    LaunchedEffect(container) {
        snapshotFlow { state.isMinimized }.collect { container.window.setMinimized(it) }
    }
    LaunchedEffect(container) {
        snapshotFlow { windowInfo.isWindowFocused }.collect { container.window.setFocused(it) }
    }
    DisposableEffect(container) {
        val toolkit = Toolkit.getDefaultToolkit()
        val listener = AWTEventListener { container.window.input() }
        toolkit.addAWTEventListener(listener, INPUT_EVENTS)
        onDispose { toolkit.removeAWTEventListener(listener) }
    }
}

/** Входящий звонок поднимает окно поверх остальных, даже свёрнутое. */
@Composable
private fun FrameWindowScope.RaiseOnIncomingCall(container: AppContainer, state: WindowState) {
    LaunchedEffect(container) {
        container.callCenter.state
            .map { it.call?.isRinging == true }
            .distinctUntilChanged()
            .collect { ringing ->
                if (!ringing) return@collect
                state.isMinimized = false
                window.toFront()
                window.requestFocus()
            }
    }
}

/** События ввода, после которых пользователь снова считается у окна. */
private const val INPUT_EVENTS: Long = AWTEvent.KEY_EVENT_MASK or AWTEvent.MOUSE_EVENT_MASK or
    AWTEvent.MOUSE_MOTION_EVENT_MASK or AWTEvent.MOUSE_WHEEL_EVENT_MASK
