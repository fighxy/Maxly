package app.orbitle

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.application
import androidx.compose.ui.window.v2.Window
import androidx.compose.ui.window.v2.WindowBoundsProvider
import androidx.compose.ui.window.v2.WindowPositionProvider
import androidx.compose.ui.window.v2.WindowSizeProvider
import androidx.compose.ui.window.v2.rememberWindowState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.domain.AuthPhase
import app.orbitle.domain.ThemeMode
import app.orbitle.platform.AppPaths
import app.orbitle.platform.DesktopOwner
import app.orbitle.presentation.auth.AuthViewModel
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.ui.auth.AuthScreen
import app.orbitle.presentation.settings.AccountLimitsText
import app.orbitle.ui.auth.AccountLimitsNotice
import app.orbitle.ui.components.ChatBackdrop
import app.orbitle.ui.components.LocalChatBackdrop
import app.orbitle.ui.main.MainScreen
import app.orbitle.calls.DesktopCallSounds
import app.orbitle.calls.DesktopCallVideo
import app.orbitle.ui.calls.CallHost
import app.orbitle.ui.calls.CenterCallActions
import app.orbitle.ui.calls.LocalCallVideo
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import app.orbitle.ui.res.painterResource
import app.orbitle.ui.theme.OrbitleTheme
import com.mohamedrejeb.calf.picker.ProvideFilePickerParentWindow
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.swing.Swing
import okio.Path.Companion.toOkioPath
import java.io.File

@OptIn(ExperimentalComposeUiApi::class)
fun main() {
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
        val windowState = rememberWindowState(
            initialBoundsProvider = WindowBoundsProvider(
                positionProvider = WindowPositionProvider.CenteredOnScreen,
                sizeProvider = WindowSizeProvider.Fixed(DpSize(1100.dp, 760.dp)),
            ),
        )
        Window(
            onCloseRequest = ::exitApplication,
            title = "Orbitle",
            icon = painterResource(R.drawable.app_icon),
            state = windowState,
            minSize = DpSize(840.dp, 600.dp),
        ) {
            // Свёрнуто ли окно и в фокусе ли оно: от этого зависят флаг активности для ядра
            // и опрос своего статуса (свёрнутое окно — фон).
            val windowInfo = LocalWindowInfo.current
            LaunchedEffect(container) {
                androidx.compose.runtime.snapshotFlow { windowState.isMinimized }.collect { container.window.setMinimized(it) }
            }
            LaunchedEffect(container) {
                androidx.compose.runtime.snapshotFlow { windowInfo.isWindowFocused }.collect { container.window.setFocused(it) }
            }
            // Клавиатура и мышь в окне: без них минуту пользователь считается отошедшим.
            DisposableEffect(container) {
                val toolkit = java.awt.Toolkit.getDefaultToolkit()
                val listener = java.awt.event.AWTEventListener { container.window.input() }
                toolkit.addAWTEventListener(listener, INPUT_EVENTS)
                onDispose { toolkit.removeAWTEventListener(listener) }
            }
            // Входящий звонок поднимает окно поверх остальных, даже свёрнутое.
            LaunchedEffect(container) {
                container.callCenter.state
                    .map { it.call?.isRinging == true }
                    .distinctUntilChanged()
                    .collect { ringing ->
                        if (!ringing) return@collect
                        windowState.requestMinimized(false)
                        window.toFront()
                        window.requestFocus()
                    }
            }
            // Ctrl+Q (⌘Q) — выход.
            app.orbitle.ui.keys.HotkeyHandler { hotkey ->
                if (hotkey.action == app.orbitle.ui.keys.HotkeyAction.QUIT) {
                    exitApplication()
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
}

/** События ввода, после которых пользователь снова считается у окна. */
private val INPUT_EVENTS: Long = java.awt.AWTEvent.KEY_EVENT_MASK or java.awt.AWTEvent.MOUSE_EVENT_MASK or
    java.awt.AWTEvent.MOUSE_MOTION_EVENT_MASK or java.awt.AWTEvent.MOUSE_WHEEL_EVENT_MASK

@Composable
private fun AppRoot(container: AppContainer) {
    val prefs by container.appearance.state.collectAsStateWithLifecycle()
    val dark = when (prefs.theme) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    OrbitleTheme(darkTheme = dark) {
        val density = LocalDensity.current
        CompositionLocalProvider(
            LocalDensity provides Density(density.density, density.fontScale * prefs.textSize.scale),
            LocalChatBackdrop provides ChatBackdrop(prefs.wallpaper, dark),
        ) {
            Root(container)
        }
    }
}

@Composable
private fun Root(container: AppContainer) {
    val phase by container.session.phase.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    when (phase) {
        AuthPhase.Restoring -> Launch()
        is AuthPhase.SignedIn -> {
            val chats = viewModel { ChatListViewModel(container.chats, container.session.connection, local = container.chatMarks, recents = container.recentSearches, serverDrafts = container.draftSync.serverDrafts, throttled = container.session.throttled) }
            val account by container.account.account.collectAsStateWithLifecycle(initialValue = null)
            LaunchedEffect(container) { container.callCenter.activate() }
            val callActions = remember { CenterCallActions(container.callCenter, scope, hasSpeaker = false) }
            val callSounds = remember { DesktopCallSounds() }
            // Звонок с клавиатуры: ответить, завершить, микрофон, камера.
            app.orbitle.ui.keys.HotkeyHandler { hotkey ->
                val call = container.callCenter.state.value.call ?: return@HotkeyHandler false
                val live = !call.state.isEnded && !call.isRinging
                when (hotkey.action) {
                    app.orbitle.ui.keys.HotkeyAction.CALL_ANSWER -> call.isRinging.also { if (it) callActions.answer(false) }
                    app.orbitle.ui.keys.HotkeyAction.CALL_HANG_UP -> true.also { callActions.hangUp() }
                    app.orbitle.ui.keys.HotkeyAction.CALL_MUTE -> live.also { if (it) callActions.toggleMute() }
                    app.orbitle.ui.keys.HotkeyAction.CALL_CAMERA -> live.also { if (it) callActions.toggleCamera() }
                    else -> false
                }
            }
            CompositionLocalProvider(LocalCallVideo provides DesktopCallVideo) {
                CallHost(container.callCenter, callActions, callSounds) {
                    MainScreen(container, chats, account, onLogout = {
                        // Места в лентах и куски истории — прежнего аккаунта.
                        app.orbitle.presentation.chat.HistoryRanges.clear()
                        app.orbitle.presentation.chat.ScrollMemory.clear()
                        scope.launch { container.session.logout() }
                    })
                }
            }
        }
        else -> {
            val auth = viewModel { AuthViewModel(container.session) }
            AuthScreen(auth)
        }
    }
    // Панель ограничений после входа: один раз, и после перезапуска тоже, если её не успели увидеть.
    val limits by container.accountLimits.state.collectAsStateWithLifecycle()
    val now = System.currentTimeMillis()
    val notice = limits?.takeIf { phase is AuthPhase.SignedIn && it.needsNotice(now) }
    if (notice != null) {
        AccountLimitsNotice(AccountLimitsText().content(notice, now), onDismiss = container.accountLimits::markShown)
    }
}

/** Пока сессия восстанавливается: тёмный фон и знак, как на заставке телефона. */
@Composable
private fun Launch() {
    Box(Modifier.fillMaxSize().background(Color(0xFF0C0E14)), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.orbitle_mark), contentDescription = null, modifier = Modifier.size(120.dp))
    }
}
