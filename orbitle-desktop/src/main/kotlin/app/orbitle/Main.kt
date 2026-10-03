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
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import app.orbitle.domain.AuthPhase
import app.orbitle.domain.ThemeMode
import app.orbitle.platform.AppPaths
import app.orbitle.presentation.auth.AuthViewModel
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.ui.auth.AuthScreen
import app.orbitle.ui.components.ChatBackdrop
import app.orbitle.ui.components.LocalChatBackdrop
import app.orbitle.ui.main.MainScreen
import app.orbitle.ui.res.painterResource
import app.orbitle.ui.theme.OrbitleTheme
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.swing.Swing
import okio.Path.Companion.toOkioPath
import java.io.File

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
            owner.resume()
            onDispose { owner.destroy() }
        }
        LaunchedEffect(container) { container.session.restoreSession() }
        Window(
            onCloseRequest = ::exitApplication,
            title = "Orbitle",
            icon = painterResource(R.drawable.app_icon),
            state = rememberWindowState(size = DpSize(1100.dp, 760.dp)),
        ) {
            CompositionLocalProvider(
                LocalLifecycleOwner provides owner,
                LocalViewModelStoreOwner provides owner,
            ) {
                AppRoot(container)
            }
        }
    }
}

/** Жизненный цикл окна: чаты перечитывают локальные пометки, когда он в состоянии RESUMED. */
private class DesktopOwner : LifecycleOwner, ViewModelStoreOwner {
    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry
    override val viewModelStore = ViewModelStore()

    fun resume() {
        registry.currentState = Lifecycle.State.RESUMED
    }

    fun destroy() {
        registry.currentState = Lifecycle.State.DESTROYED
        viewModelStore.clear()
    }
}

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
            val chats = viewModel { ChatListViewModel(container.chats, container.session.connection, local = container.chatMarks) }
            val account by container.account.account.collectAsStateWithLifecycle(initialValue = null)
            MainScreen(container, chats, account, onLogout = { scope.launch { container.session.logout() } })
        }
        else -> {
            val auth = viewModel { AuthViewModel(container.session) }
            AuthScreen(auth)
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
