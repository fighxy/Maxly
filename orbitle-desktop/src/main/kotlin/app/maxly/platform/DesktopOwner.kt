package app.maxly.platform

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner

/**
 * Жизненный цикл окна. RESUMED — окно видно и в фокусе ([WindowActivity.looking]): только тогда
 * открытый чат отмечает сообщения прочитанными, а чаты перечитывают локальные пометки. Свёрнутое
 * или неактивное окно — STARTED: экран живёт, но отметок прочтения нет.
 *
 * @param checkThread проверять, что состояние меняется в главном потоке; тесты без него.
 */
class DesktopOwner(checkThread: Boolean = true) : LifecycleOwner, ViewModelStoreOwner {
    private val registry = if (checkThread) LifecycleRegistry(this) else LifecycleRegistry.createUnsafe(this)
    override val lifecycle: Lifecycle get() = registry
    override val viewModelStore = ViewModelStore()

    /** Новое состояние окна; после [destroy] не меняется. */
    fun moveTo(state: Lifecycle.State) {
        if (registry.currentState == Lifecycle.State.DESTROYED) return
        registry.currentState = state
    }

    fun destroy() {
        registry.currentState = Lifecycle.State.DESTROYED
        viewModelStore.clear()
    }

    companion object {
        /** Состояние окна, на которое пользователь смотрит ([looking]) или нет. */
        fun stateOf(looking: Boolean): Lifecycle.State = if (looking) Lifecycle.State.RESUMED else Lifecycle.State.STARTED
    }
}
