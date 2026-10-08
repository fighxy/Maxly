package app.orbitle

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import app.orbitle.calls.AndroidCallSounds
import app.orbitle.calls.AndroidCallSystem
import app.orbitle.calls.AndroidCallVideo
import app.orbitle.calls.AndroidCalls
import app.orbitle.calls.CallPermissions
import app.orbitle.ui.calls.CallHost
import app.orbitle.ui.calls.CenterCallActions
import app.orbitle.ui.calls.LocalCallVideo
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import app.orbitle.domain.ThemeMode
import app.orbitle.ui.components.ChatBackdrop
import app.orbitle.ui.components.LocalChatBackdrop
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.domain.AuthPhase
import app.orbitle.presentation.auth.AuthViewModel
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.ui.auth.AuthScreen
import app.orbitle.presentation.settings.AccountLimitsText
import app.orbitle.ui.auth.AccountLimitsNotice
import app.orbitle.ui.main.MainScreen
import app.orbitle.ui.theme.OrbitleTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onResume() {
        super.onResume()
        // Разрешение на книгу могли дать или отозвать в настройках, пока приложение было в фоне.
        val granted = androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CONTACTS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        (application as OrbitleApp).container.syncAddressBook(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val container = (application as OrbitleApp).container
        CallPermissions.attach(this)
        handleCallIntent(intent)
        setContent {
            val prefs by container.appearance.state.collectAsStateWithLifecycle()
            val dark = when (prefs.theme) {
                ThemeMode.SYSTEM -> isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }
            // Значки строки состояния под выбранную тему, а не под системную.
            DisposableEffect(dark) {
                val style = if (dark) SystemBarStyle.dark(AndroidColor.TRANSPARENT) else SystemBarStyle.light(AndroidColor.TRANSPARENT, AndroidColor.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
                onDispose {}
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    override fun onDestroy() {
        CallPermissions.detach()
        super.onDestroy()
    }

    /** «Ответить» и нажатие на уведомление звонка. */
    private fun handleCallIntent(intent: Intent?) {
        val container = (application as OrbitleApp).container
        when (intent?.action) {
            AndroidCallSystem.ACTION_ANSWER -> AndroidCalls.answer(container, video = false)
            AndroidCallSystem.ACTION_OPEN -> container.callCenter.expand()
            else -> return
        }
        intent?.action = null
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
            LaunchedEffect(container) {
                container.callCenter.activate()
                // Без разрешения на уведомления входящий звонок в фоне не покажется.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) CallPermissions.ensure(Manifest.permission.POST_NOTIFICATIONS)
            }
            val context = LocalContext.current
            val callActions = remember {
                CenterCallActions(container.callCenter, container.scope, hasSpeaker = true) { video -> AndroidCalls.answer(container, video) }
            }
            val callSounds = remember { AndroidCallSounds(context.applicationContext) }
            val callState by container.callCenter.state.collectAsStateWithLifecycle()
            // Пока идёт звонок, экран не гаснет сам.
            val activity = context as? android.app.Activity
            DisposableEffect(callState.call != null) {
                if (callState.call != null) activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                onDispose { activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
            }
            CompositionLocalProvider(LocalCallVideo provides AndroidCallVideo) {
                CallHost(container.callCenter, callActions, callSounds, onShareLink = { AndroidCalls.share(context, it) }) {
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

/** Экран запуска, пока сессия восстанавливается: тот же фон и знак, что у системной заставки. */
@Composable
private fun Launch() {
    Box(Modifier.fillMaxSize().background(Color(0xFF0C0E14)), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.orbitle_mark), contentDescription = null, modifier = Modifier.size(120.dp))
    }
}
