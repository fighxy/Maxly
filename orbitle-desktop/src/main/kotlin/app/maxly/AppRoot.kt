package app.maxly

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.maxly.calls.DesktopCallSounds
import app.maxly.calls.DesktopCallVideo
import app.maxly.data.diagnostics.AppLog
import app.maxly.domain.AuthPhase
import app.maxly.domain.ThemeMode
import app.maxly.presentation.auth.AuthViewModel
import app.maxly.presentation.calls.CallCenter
import app.maxly.presentation.chat.HistoryRanges
import app.maxly.presentation.chat.ScrollMemory
import app.maxly.presentation.chatlist.ChatListViewModel
import app.maxly.presentation.settings.AccountLimitsText
import app.maxly.ui.auth.AccountLimitsNotice
import app.maxly.ui.auth.AuthScreen
import app.maxly.ui.calls.CallActions
import app.maxly.ui.calls.CallHost
import app.maxly.ui.calls.CenterCallActions
import app.maxly.ui.calls.LocalCallVideo
import app.maxly.ui.components.ChatBackdrop
import app.maxly.ui.components.LocalChatBackdrop
import app.maxly.ui.keys.HotkeyAction
import app.maxly.ui.keys.HotkeyHandler
import app.maxly.ui.main.MainScreen
import app.maxly.ui.res.painterResource
import app.maxly.ui.theme.OrbitleTheme
import kotlinx.coroutines.launch

/** Тема, размер текста и обои поверх всего окна. */
@Composable
internal fun AppRoot(container: AppContainer) {
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

/** Заставка, вход или главный экран — по фазе сессии. */
@Composable
private fun Root(container: AppContainer) {
    val phase by container.session.phase.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    LaunchedEffect(phase::class) { AppLog.i("app", "Сессия: ${phase::class.simpleName}") }
    when (phase) {
        AuthPhase.Restoring -> Launch()
        is AuthPhase.SignedIn -> {
            val chats = viewModel {
                ChatListViewModel(
                    container.chats,
                    container.session.connection,
                    local = container.chatMarks,
                    recents = container.recentSearches,
                    serverDrafts = container.draftSync.serverDrafts,
                    throttled = container.session.throttled,
                )
            }
            val account by container.account.account.collectAsStateWithLifecycle(initialValue = null)
            LaunchedEffect(container) { container.callCenter.activate() }
            val callActions = remember { CenterCallActions(container.callCenter, scope, hasSpeaker = false) }
            val callSounds = remember { DesktopCallSounds() }
            CallHotkeys(container.callCenter, callActions)
            CompositionLocalProvider(LocalCallVideo provides DesktopCallVideo) {
                CallHost(container.callCenter, callActions, callSounds) {
                    MainScreen(container, chats, account, onLogout = {
                        // Места в лентах и куски истории — прежнего аккаунта.
                        HistoryRanges.clear()
                        ScrollMemory.clear()
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

/** Звонок с клавиатуры: ответить, завершить, микрофон, камера. */
@Composable
private fun CallHotkeys(center: CallCenter, actions: CallActions) {
    HotkeyHandler { hotkey ->
        val call = center.state.value.call ?: return@HotkeyHandler false
        val live = !call.state.isEnded && !call.isRinging
        when (hotkey.action) {
            HotkeyAction.CALL_ANSWER -> call.isRinging.also { if (it) actions.answer(false) }
            HotkeyAction.CALL_HANG_UP -> true.also { actions.hangUp() }
            HotkeyAction.CALL_MUTE -> live.also { if (it) actions.toggleMute() }
            HotkeyAction.CALL_CAMERA -> live.also { if (it) actions.toggleCamera() }
            else -> false
        }
    }
}

/** Пока сессия восстанавливается: тёмный фон и знак, как на заставке телефона. */
@Composable
private fun Launch() {
    Box(Modifier.fillMaxSize().background(Color(0xFF0C0E14)), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.orbitle_mark), contentDescription = null, modifier = Modifier.size(120.dp))
    }
}
