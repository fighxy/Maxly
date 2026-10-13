package app.maxly.platform

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.window.WindowState

/** Состояние главного окна: просмотр фото и видео разворачивает его во весь экран. */
val LocalMainWindowState = staticCompositionLocalOf<WindowState?> { null }
