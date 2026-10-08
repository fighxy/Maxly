package app.orbitle.presentation.chat

import app.orbitle.data.PreferenceStore
import app.orbitle.domain.VideoNoteRecording
import app.orbitle.domain.VoiceRecording
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Что пишет кнопка справа от поля ввода. */
enum class RecordingMode { VOICE, VIDEO }

/** Готовая запись для отправки. */
sealed interface RecordedDraft {
    data class Voice(val recording: VoiceRecording) : RecordedDraft

    data class Note(val recording: VideoNoteRecording) : RecordedDraft
}

/** Микрофон и камера платформы для записи из поля ввода. Все вызовы — на главном потоке. */
interface ComposerRecorder {
    enum class Access { GRANTED, ASK, DENIED }

    /** Есть ли доступ (без запроса, чтобы нажатие не ждало). */
    fun access(mode: RecordingMode): Access

    /** Спросить доступ у системы; запись этим нажатием не начинается. */
    suspend fun requestAccess(mode: RecordingMode): Boolean

    /** Включить микрофон (или камеру с микрофоном). `false` — не вышло. */
    suspend fun start(mode: RecordingMode): Boolean

    /** Остановить и отдать запись; `null` — слишком коротко или не вышло. */
    suspend fun stop(mode: RecordingMode): RecordedDraft?

    /** Выбросить идущую запись. */
    suspend fun cancel(mode: RecordingMode)

    /** Запись упёрлась в предел длины: контроллер её отправляет. */
    var onLimit: (() -> Unit)?
}

/** Режим записи запоминается на устройстве, как на iOS. */
class RecordingModeSettings(private val store: PreferenceStore) {
    fun load(): RecordingMode = RecordingMode.entries.firstOrNull { it.name == store.get(KEY) } ?: RecordingMode.VOICE

    fun save(mode: RecordingMode) = store.put(KEY, mode.name)

    private companion object {
        const val KEY = "chat.recordMode"
    }
}

/**
 * Запись голосового или кружка из поля ввода — порт iOS `RecordingSession`.
 *
 * Кнопка справа (когда поле пустое) — микрофон или камера. Удержание — запись, отпустить —
 * отправить. Увести палец влево — отмена, вверх — закрепить запись, тогда её отправляет
 * нажатие той же кнопки, а корзина отменяет. Короткое нажатие переключает микрофон и камеру.
 * Запись включается сразу под пальцем, полоса записи появляется через [holdDelayMs].
 */
class RecordingController(
    private val recorder: ComposerRecorder,
    private val scope: CoroutineScope,
    private val settings: RecordingModeSettings? = null,
    private val holdDelayMs: Long = HOLD_DELAY_MS,
) {
    enum class Phase {
        IDLE,

        /** Палец на кнопке, полосы записи ещё нет (короткое нажатие — смена режима). */
        PRESSING,
        RECORDING,

        /** Закреплена свайпом вверх: палец можно убрать. */
        LOCKED,

        /** Остановка и подготовка файла. */
        FINISHING,
    }

    data class State(
        val mode: RecordingMode = RecordingMode.VOICE,
        val phase: Phase = Phase.IDLE,
        /** Режим идущей записи. */
        val recording: RecordingMode = RecordingMode.VOICE,
        /** Сдвиг пальца влево и вверх, dp (≤ 0). */
        val dragX: Float = 0f,
        val dragY: Float = 0f,
        val hint: String? = null,
    ) {
        /** Вместо поля ввода — полоса записи. */
        val isActive: Boolean get() = phase == Phase.RECORDING || phase == Phase.LOCKED || phase == Phase.FINISHING

        val isVideo: Boolean get() = isActive && recording == RecordingMode.VIDEO
    }

    private val _state = MutableStateFlow(State(mode = settings?.load() ?: RecordingMode.VOICE))
    val state: StateFlow<State> = _state.asStateFlow()

    /** Готовая запись. */
    var onRecorded: (RecordedDraft) -> Unit = {}

    /** Запись началась: остановить воспроизведение голосовых. */
    var onStart: () -> Unit = {}

    private val queue = Mutex()
    private var pressJob: Job? = null
    private var hintJob: Job? = null
    private var warming = false
    private var requesting = false
    private var attempt = 0
    private var lockedInPress = false

    init {
        recorder.onLimit = { send() }
    }

    /** Палец лёг на кнопку. */
    fun press() {
        val current = _state.value
        if (current.phase != Phase.IDLE) return
        val mode = current.mode
        attempt += 1
        lockedInPress = false
        _state.update { it.copy(phase = Phase.PRESSING) }
        when (recorder.access(mode)) {
            ComposerRecorder.Access.GRANTED -> {
                warming = true
                _state.update { it.copy(recording = mode) }
                onStart()
                val number = attempt
                enqueue { startRecorder(mode, number) }
                pressJob = scope.launch {
                    delay(holdDelayMs)
                    if (_state.value.phase != Phase.PRESSING || !warming) return@launch
                    warming = false
                    _state.update { it.copy(phase = Phase.RECORDING) }
                }
            }
            ComposerRecorder.Access.ASK -> {
                // Первое касание спрашивает систему; запись не начинается.
                requesting = true
                scope.launch {
                    val granted = recorder.requestAccess(mode)
                    requesting = false
                    if (!granted) show(denied(mode))
                }
            }
            ComposerRecorder.Access.DENIED -> {
                _state.update { it.copy(phase = Phase.IDLE) }
                show(denied(mode))
            }
        }
    }

    /**
     * Клавиша записи (ПК): запись начинается сразу закреплённой — её отправляет повторное
     * нажатие или кнопка, отменяет Esc или корзина.
     */
    fun toggleByKey() {
        when (_state.value.phase) {
            Phase.IDLE -> {
                val mode = _state.value.mode
                when (recorder.access(mode)) {
                    ComposerRecorder.Access.GRANTED -> Unit
                    ComposerRecorder.Access.ASK -> {
                        scope.launch { if (!recorder.requestAccess(mode)) show(denied(mode)) }
                        return
                    }
                    ComposerRecorder.Access.DENIED -> {
                        show(denied(mode))
                        return
                    }
                }
                attempt += 1
                warming = false
                lockedInPress = false
                _state.update { it.copy(phase = Phase.LOCKED, recording = mode, dragX = 0f, dragY = 0f) }
                onStart()
                val number = attempt
                enqueue { startRecorder(mode, number) }
            }
            Phase.RECORDING, Phase.LOCKED -> send()
            else -> Unit
        }
    }

    /** Палец сдвинулся на [dx], [dy] dp от места касания. */
    fun move(dx: Float, dy: Float) {
        if (_state.value.phase != Phase.RECORDING) return
        val x = minOf(0f, dx)
        val y = minOf(0f, dy)
        when {
            x < -RecordingGesture.CANCEL_DISTANCE -> cancel()
            y < -RecordingGesture.LOCK_DISTANCE -> {
                lockedInPress = true
                _state.update { it.copy(phase = Phase.LOCKED, dragX = 0f, dragY = 0f) }
            }
            else -> _state.update { it.copy(dragX = x, dragY = y) }
        }
    }

    /** Палец отпущен. */
    fun release() {
        when (_state.value.phase) {
            Phase.PRESSING -> {
                pressJob?.cancel()
                pressJob = null
                _state.update { it.copy(phase = Phase.IDLE) }
                if (warming) {
                    // Короткое касание: включённый под пальцем микрофон или камера не нужны.
                    warming = false
                    discard(_state.value.recording)
                    toggleMode()
                } else if (!requesting) {
                    toggleMode()
                }
            }
            Phase.RECORDING -> send()
            Phase.LOCKED -> if (lockedInPress) lockedInPress = false else send()
            else -> Unit
        }
        _state.update { it.copy(dragX = 0f, dragY = 0f) }
    }

    /** Жест оборвался без отпускания: начатая запись закрепляется, нажатие без записи забывается. */
    fun interrupt() {
        when (_state.value.phase) {
            Phase.PRESSING -> {
                pressJob?.cancel()
                pressJob = null
                if (warming) {
                    warming = false
                    discard(_state.value.recording)
                }
                _state.update { it.copy(phase = Phase.IDLE) }
            }
            Phase.RECORDING -> _state.update { it.copy(phase = Phase.LOCKED) }
            else -> Unit
        }
        lockedInPress = false
        _state.update { it.copy(dragX = 0f, dragY = 0f) }
    }

    /** Остановить и отправить. */
    fun send() {
        val phase = _state.value.phase
        if (phase != Phase.RECORDING && phase != Phase.LOCKED) return
        _state.update { it.copy(phase = Phase.FINISHING, dragX = 0f, dragY = 0f) }
        val mode = _state.value.recording
        val number = attempt
        enqueue {
            val draft = recorder.stop(mode)
            if (number == attempt && _state.value.phase == Phase.FINISHING) _state.update { it.copy(phase = Phase.IDLE) }
            if (draft != null) onRecorded(draft) else show(tooShort(mode))
        }
    }

    /** Выбросить запись: свайп влево, корзина, уход с экрана. */
    fun cancel() {
        pressJob?.cancel()
        pressJob = null
        val state = _state.value
        when {
            state.phase == Phase.PRESSING && warming -> {
                warming = false
                discard(state.recording)
            }
            state.phase == Phase.RECORDING || state.phase == Phase.LOCKED -> discard(state.recording)
        }
        if (state.phase != Phase.FINISHING) _state.update { it.copy(phase = Phase.IDLE) }
        _state.update { it.copy(dragX = 0f, dragY = 0f) }
    }

    private suspend fun startRecorder(mode: RecordingMode, number: Int) {
        if (recorder.start(mode)) return
        if (number != attempt) return
        val phase = _state.value.phase
        if (phase != Phase.PRESSING && phase != Phase.RECORDING && phase != Phase.LOCKED) return
        pressJob?.cancel()
        pressJob = null
        warming = false
        _state.update { it.copy(phase = Phase.IDLE) }
        show(if (mode == RecordingMode.VOICE) "Не удалось включить микрофон" else "Не удалось включить камеру")
    }

    private fun discard(mode: RecordingMode) = enqueue { recorder.cancel(mode) }

    /** Включение, остановка и выброс идут по очереди: следующее нажатие ждёт выключения. */
    private fun enqueue(operation: suspend () -> Unit) {
        scope.launch { queue.withLock { operation() } }
    }

    private fun toggleMode() {
        val next = if (_state.value.mode == RecordingMode.VOICE) RecordingMode.VIDEO else RecordingMode.VOICE
        _state.update { it.copy(mode = next) }
        settings?.save(next)
        show(
            if (next == RecordingMode.VOICE) "Удерживайте, чтобы записать голосовое. Нажмите — для видеосообщения"
            else "Удерживайте, чтобы записать видеосообщение. Нажмите — для голосового",
        )
    }

    private fun denied(mode: RecordingMode) =
        if (mode == RecordingMode.VOICE) "Нет доступа к микрофону. Разрешите его в настройках"
        else "Нет доступа к камере или микрофону. Разрешите их в настройках"

    private fun tooShort(mode: RecordingMode) =
        if (mode == RecordingMode.VOICE) RecordingGesture.HOLD_HINT else "Удерживайте, чтобы записать видеосообщение"

    private fun show(text: String) {
        _state.update { it.copy(hint = text) }
        hintJob?.cancel()
        hintJob = scope.launch {
            delay(2_500)
            _state.update { it.copy(hint = null) }
        }
    }

    companion object {
        /** Нажатие короче — смена режима, дольше — запись. */
        const val HOLD_DELAY_MS = 150L

        /** Кружок — не длиннее минуты. */
        const val VIDEO_NOTE_LIMIT_MS = 60_000L
    }
}
