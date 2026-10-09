package app.orbitle

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
import app.orbitle.calls.DesktopCallSounds
import app.orbitle.calls.DesktopCallVideo
import app.orbitle.data.diagnostics.AppLog
import app.orbitle.domain.AuthPhase
import app.orbitle.domain.ThemeMode
import app.orbitle.presentation.auth.AuthViewModel
import app.orbitle.presentation.calls.CallCenter
import app.orbitle.presentation.chat.HistoryRanges
import app.orbitle.presentation.chat.ScrollMemory
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.presentation.settings.AccountLimitsText
import app.orbitle.ui.auth.AccountLimitsNotice
import app.orbitle.ui.auth.AuthScreen
import app.orbitle.ui.calls.CallActions
import app.orbitle.ui.calls.CallHost
import app.orbitle.ui.calls.CenterCallActions
import app.orbitle.ui.calls.LocalCallVideo
import app.orbitle.ui.components.ChatBackdrop
import app.orbitle.ui.components.LocalChatBackdrop
import app.orbitle.ui.keys.HotkeyAction
import app.orbitle.ui.keys.HotkeyHandler
import app.orbitle.ui.main.MainScreen
import app.orbitle.ui.res.painterResource
import app.orbitle.ui.theme.OrbitleTheme
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
