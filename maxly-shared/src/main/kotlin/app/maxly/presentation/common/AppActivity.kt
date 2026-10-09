package app.maxly.presentation.common

import app.maxly.presentation.calls.CallCenterState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * Флаг активности приложения для ядра (`MaxClient.setInteractive`): смотрит ли пользователь
 * в приложение. Ядро кладёт его в `interactive` пингов и `LOGIN`, а в режиме призрака только
 * запоминает и шлёт `false` — сводить флаг с режимом призрака приложению не нужно.
 */
object AppActivity {
    /** Звонок идёт (принят или исходящий, ещё не завершён): входящий, пока звонит, не считается. */
    fun inCall(state: CallCenterState): Boolean {
        val call = state.call ?: return false
        return !call.state.isEnded && !call.isRinging
    }

    /**
     * Android: приложение на переднем плане при разблокированном экране или идёт звонок. Во время
     * звонка флаг остаётся `true` и в фоне: ядро шлёт `PING` раз в 29 с с этим флагом.
     */
    fun android(foreground: Boolean, unlocked: Boolean, inCall: Boolean): Boolean = (foreground && unlocked) || inCall

    /**
     * Desktop: окно видно, в фокусе и в нём недавно был ввод ([windowActive]) или идёт звонок —
     * тогда и в свёрнутом или неактивном окне.
     */
    fun desktop(windowActive: Boolean, inCall: Boolean): Boolean = windowActive || inCall

    /** Шлёт [report] каждое новое значение [active], первое — сразу. */
    fun report(scope: CoroutineScope, active: Flow<Boolean>, report: suspend (Boolean) -> Unit): Job =
        scope.launch { active.distinctUntilChanged().collect { report(it) } }
}
