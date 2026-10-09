package app.maxly.platform

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.transformLatest

/**
 * Смотрит ли пользователь в окно. Пишет Main.kt: свёрнуто ли окно, в фокусе ли оно и ввод
 * (клавиатура, мышь) в нём.
 *
 * - [shown] — окно не свёрнуто: свой статус опрашивается только тогда;
 * - [looking] — окно видно и в фокусе: только тогда открытый чат отмечается прочитанным;
 * - [active] — флаг активности для ядра: [looking] и ввод был не дольше [idleMs] назад.
 *
 * @param clock текущее время в мс, в тестах подменяется.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class WindowActivity(
    private val clock: () -> Long = System::currentTimeMillis,
    private val idleMs: Long = IDLE_MS,
) {
    private val minimized = MutableStateFlow(false)
    private val focused = MutableStateFlow(false)
    private val lastInput = MutableStateFlow(clock())

    private val _shown = MutableStateFlow(true)
    val shown: StateFlow<Boolean> = _shown.asStateFlow()

    val looking: Flow<Boolean> = combine(minimized, focused) { min, focus -> isLooking(min, focus) }.distinctUntilChanged()

    val active: Flow<Boolean> = looking
        .flatMapLatest { if (it) attention() else flowOf(false) }
        .distinctUntilChanged()

    fun setMinimized(value: Boolean) {
        minimized.value = value
        _shown.value = !value
    }

    /** Фокус пришёл — пользователь вернулся к окну: это тоже ввод. */
    fun setFocused(value: Boolean) {
        if (value) lastInput.value = clock()
        focused.value = value
    }

    /** Ввод в окне. Отметка обновляется не чаще раза в секунду: движение мыши частое. */
    fun input() {
        val now = clock()
        if (now - lastInput.value >= INPUT_STEP_MS) lastInput.value = now
    }

    /** `true` с каждым вводом, `false` после [idleMs] без него. */
    private fun attention(): Flow<Boolean> = lastInput.transformLatest { last ->
        val left = last + idleMs - clock()
        if (left > 0) {
            emit(true)
            delay(left)
        }
        emit(false)
    }

    companion object {
        /** Без ввода дольше этого (мс) пользователь считается отошедшим. */
        const val IDLE_MS = 60_000L
        private const val INPUT_STEP_MS = 1_000L

        /** Окно видно (не свёрнуто) и в фокусе. */
        fun isLooking(minimized: Boolean, focused: Boolean): Boolean = !minimized && focused
    }
}
