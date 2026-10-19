package app.maxly.presentation.chat

import app.maxly.data.PreferenceStore
import app.maxly.domain.VideoNoteRecording
import app.maxly.domain.VoiceRecording
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

/** Что пишет кнопка справа от поля ввода: микрофон — голосовое, камера — кружок. */
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

    /**
     * Своя подсказка, почему последний [start] вернул `false` (например, нечем сжать видео);
     * `null` — обычное «не удалось включить микрофон/камеру».
     */
    fun startFailure(mode: RecordingMode): String? = null

    /** Остановить и отдать запись; `null` — слишком коротко или не вышло. */
    suspend fun stop(mode: RecordingMode): RecordedDraft?

    /** Выбросить идущую запись. */
    suspend fun cancel(mode: RecordingMode)

    /** Кусок записанного кружка от [fromMs] до [toMs]; `null` — не вышло. */
    suspend fun trim(recording: VideoNoteRecording, fromMs: Long, toMs: Long): VideoNoteRecording? = recording

    /** Выбросить записанный кружок с просмотра. */
    suspend fun discard(recording: VideoNoteRecording) {}

    /** Пауза ([paused] = `true`) или продолжение закреплённой записи. `false` — не умеет. */
    fun setPaused(mode: RecordingMode, paused: Boolean): Boolean = false

    /** Кусок записанного голосового от [fromMs] до [toMs]; `null` — не вышло. */
    suspend fun trimVoice(recording: VoiceRecording, fromMs: Long, toMs: Long): VoiceRecording? = recording

    /** Выбросить записанное голосовое с просмотра. */
    suspend fun discardVoice(recording: VoiceRecording) {}

    /** Запись упёрлась в предел длины: контроллер её отправляет. */
    var onLimit: (() -> Unit)?
}

/**
 * Запись голосового или кружка из поля ввода — порт iOS `RecordingSession`:
 * у каждой записи своя кнопка.
 *
 * Микрофон: удержание — голосовое, короткое нажатие — подсказка. Камера: удержание — кружок,
 * короткое нажатие — снимок ([onCameraTap]). Отпустить — отправить. Увести палец влево —
 * отмена, вверх — закрепить запись, тогда её отправляет нажатие той же кнопки, а корзина
 * отменяет. Микрофон включается сразу под пальцем, полоса записи появляется через
 * [holdDelayMs]; камера для кружка — только через [videoHoldDelayMs], чтобы касание ради
 * снимка её не занимало.
 */
class RecordingController(
    private val recorder: ComposerRecorder,
    private val scope: CoroutineScope,
    private val holdDelayMs: Long = HOLD_DELAY_MS,
    private val videoHoldDelayMs: Long = VIDEO_HOLD_DELAY_MS,
) {
    enum class Phase {
        IDLE,

        /** Палец на кнопке, полосы записи ещё нет (короткое нажатие — подсказка или снимок). */
        PRESSING,
        RECORDING,

        /** Закреплена свайпом вверх: палец можно убрать. */
        LOCKED,

        /** Остановка и подготовка файла. */
        FINISHING,

        /** Кружок остановлен кнопкой «стоп»: просмотр, обрезка, отправка или корзина ([State.review]). */
        REVIEWING,
    }

    /**
     * Записанный кружок на просмотре: выбранный кусок [start]..[end] — доли длительности.
     * Короче [NOTE_MINIMUM_MS] кусок не бывает.
     */
    data class NoteReview(val recording: VideoNoteRecording, val start: Float = 0f, val end: Float = 1f) {
        val minimumSpan: Float
            get() = if (recording.durationMs <= 0) 1f else minOf(1f, NOTE_MINIMUM_MS.toFloat() / recording.durationMs)
        val fromMs: Long get() = (start * recording.durationMs).toLong()
        val toMs: Long get() = (end * recording.durationMs).toLong()
        val isWhole: Boolean get() = start <= 0.001f && end >= 0.999f
    }

    /** Записанное голосовое на просмотре: выбранный кусок [start]..[end] — доли длительности. */
    data class VoiceReview(val recording: VoiceRecording, val start: Float = 0f, val end: Float = 1f) {
        val minimumSpan: Float
            get() = if (recording.durationMs <= 0) 1f else minOf(1f, NOTE_MINIMUM_MS.toFloat() / recording.durationMs)
        val fromMs: Long get() = (start * recording.durationMs).toLong()
        val toMs: Long get() = (end * recording.durationMs).toLong()
        val isWhole: Boolean get() = start <= 0.001f && end >= 0.999f
        val selectedMs: Long get() = toMs - fromMs
    }

    data class State(
        val phase: Phase = Phase.IDLE,
        /** Кнопка текущего нажатия или записи: другая на это время прячется. */
        val recording: RecordingMode = RecordingMode.VOICE,
        /** Сдвиг пальца влево и вверх, dp (≤ 0). */
        val dragX: Float = 0f,
        val dragY: Float = 0f,
        val hint: String? = null,
        /** Кружок на просмотре ([Phase.REVIEWING]). */
        val review: NoteReview? = null,
        /** Голосовое на просмотре ([Phase.REVIEWING]). */
        val voiceReview: VoiceReview? = null,
        /** Закреплённая запись на паузе. */
        val paused: Boolean = false,
    ) {
        /** Вместо поля ввода — полоса записи. */
        val isActive: Boolean
            get() = phase == Phase.RECORDING || phase == Phase.LOCKED || phase == Phase.FINISHING || phase == Phase.REVIEWING

        val isVideo: Boolean get() = isActive && recording == RecordingMode.VIDEO

        /** Нажатие или запись идут на кнопке [mode]. */
        fun owns(mode: RecordingMode): Boolean = phase != Phase.IDLE && recording == mode
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Готовая запись. */
    var onRecorded: (RecordedDraft) -> Unit = {}

    /** Запись началась: остановить воспроизведение голосовых. */
    var onStart: () -> Unit = {}

    /** Короткое нажатие камеры: снимок. */
    var onCameraTap: () -> Unit = {}

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

    /** Палец лёг на кнопку [mode]. */
    fun press(mode: RecordingMode = RecordingMode.VOICE) {
        if (_state.value.phase != Phase.IDLE) return
        attempt += 1
        lockedInPress = false
        _state.update { it.copy(phase = Phase.PRESSING, recording = mode) }
        if (mode == RecordingMode.VIDEO) {
            // Камера включается, только если палец держат: короткое касание — снимок.
            pressJob = scope.launch {
                delay(videoHoldDelayMs)
                if (_state.value.phase == Phase.PRESSING) beginHold(mode)
            }
            return
        }
        beginHold(mode)
    }

    /** Удержание дошло до записи: доступ, включение рекордера и полоса записи. */
    private fun beginHold(mode: RecordingMode) {
        when (recorder.access(mode)) {
            ComposerRecorder.Access.GRANTED -> {
                warming = true
                onStart()
                val number = attempt
                enqueue { startRecorder(mode, number) }
                // Кружок уже выдержал свою паузу: полоса записи сразу.
                val wait = if (mode == RecordingMode.VIDEO) 0L else holdDelayMs
                pressJob = scope.launch {
                    if (wait > 0) delay(wait)
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
    fun toggleByKey(mode: RecordingMode = RecordingMode.VOICE) {
        when (_state.value.phase) {
            Phase.IDLE -> {
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
            Phase.RECORDING, Phase.LOCKED, Phase.REVIEWING -> send()
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
                val mode = _state.value.recording
                _state.update { it.copy(phase = Phase.IDLE) }
                if (warming) {
                    // Короткое касание: включённый под пальцем микрофон не нужен.
                    warming = false
                    discard(mode)
                }
                if (!requesting) tapped(mode)
            }
            Phase.RECORDING -> send()
            Phase.LOCKED -> if (lockedInPress) lockedInPress = false else send()
            Phase.REVIEWING -> send()
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

    /** Пауза и продолжение закреплённой записи. */
    fun togglePause() {
        val state = _state.value
        if (state.phase != Phase.LOCKED) return
        val next = !state.paused
        if (recorder.setPaused(state.recording, next)) _state.update { it.copy(paused = next) }
    }

    /** Закреплённое голосовое — на просмотр: прослушать, обрезать, отправить или выбросить. */
    private fun stopVoiceForReview() {
        _state.update { it.copy(phase = Phase.FINISHING, dragX = 0f, dragY = 0f, paused = false) }
        val number = attempt
        enqueue {
            val voice = (recorder.stop(RecordingMode.VOICE) as? RecordedDraft.Voice)?.recording
            if (number != attempt || _state.value.phase != Phase.FINISHING) {
                if (voice != null) recorder.discardVoice(voice)
                return@enqueue
            }
            if (voice == null) {
                _state.update { it.copy(phase = Phase.IDLE) }
                show(tooShort(RecordingMode.VOICE))
            } else {
                _state.update { it.copy(phase = Phase.REVIEWING, voiceReview = VoiceReview(voice)) }
            }
        }
    }

    /** Ручки обрезки голосового: кусок не короче секунды. */
    fun trimVoice(start: Float, end: Float) {
        val review = _state.value.voiceReview ?: return
        val span = review.minimumSpan
        val from = start.coerceIn(0f, 1f - span)
        val to = end.coerceIn(from + span, 1f)
        _state.update { it.copy(voiceReview = review.copy(start = from, end = to)) }
    }

    private fun sendVoiceReview() {
        val review = _state.value.voiceReview ?: return
        _state.update { it.copy(phase = Phase.FINISHING) }
        val number = attempt
        enqueue {
            val voice = if (review.isWhole) review.recording else recorder.trimVoice(review.recording, review.fromMs, review.toMs)
            if (!review.isWhole && voice != null) recorder.discardVoice(review.recording)
            if (number == attempt && _state.value.phase == Phase.FINISHING) _state.update { it.copy(phase = Phase.IDLE, voiceReview = null) }
            if (voice != null) onRecorded(RecordedDraft.Voice(voice)) else show("Голосовое не обрезалось. Попробуйте ещё раз")
        }
    }

    /** Закреплённая запись — на просмотр: её можно обрезать, отправить или выбросить. */
    fun stopForReview() {
        val state = _state.value
        if (state.phase != Phase.LOCKED) return
        if (state.recording == RecordingMode.VOICE) {
            stopVoiceForReview()
            return
        }
        _state.update { it.copy(phase = Phase.FINISHING, dragX = 0f, dragY = 0f, paused = false) }
        val number = attempt
        enqueue {
            val note = (recorder.stop(RecordingMode.VIDEO) as? RecordedDraft.Note)?.recording
            if (number != attempt || _state.value.phase != Phase.FINISHING) {
                if (note != null) recorder.discard(note)
                return@enqueue
            }
            if (note == null) {
                _state.update { it.copy(phase = Phase.IDLE) }
                show(tooShort(RecordingMode.VIDEO))
            } else {
                _state.update { it.copy(phase = Phase.REVIEWING, review = NoteReview(note)) }
            }
        }
    }

    /** Ручки обрезки на просмотре: кусок не короче секунды и в пределах ролика. */
    fun trim(start: Float, end: Float) {
        val review = _state.value.review ?: return
        val span = review.minimumSpan
        val from = start.coerceIn(0f, 1f - span)
        val to = end.coerceIn(from + span, 1f)
        _state.update { it.copy(review = review.copy(start = from, end = to)) }
    }

    /** Отправить кружок с просмотра: выбранный кусок. */
    private fun sendReview() {
        val review = _state.value.review ?: return
        _state.update { it.copy(phase = Phase.FINISHING) }
        val number = attempt
        enqueue {
            val note = if (review.isWhole) review.recording else recorder.trim(review.recording, review.fromMs, review.toMs)
            if (!review.isWhole && note != null) recorder.discard(review.recording)
            if (number == attempt && _state.value.phase == Phase.FINISHING) _state.update { it.copy(phase = Phase.IDLE, review = null) }
            if (note != null) onRecorded(RecordedDraft.Note(note)) else show("Кружок не обрезался. Попробуйте ещё раз")
        }
    }

    /** Остановить и отправить. */
    fun send() {
        val phase = _state.value.phase
        if (phase == Phase.REVIEWING) {
            if (_state.value.voiceReview != null) sendVoiceReview() else sendReview()
            return
        }
        if (phase != Phase.RECORDING && phase != Phase.LOCKED) return
        _state.update { it.copy(phase = Phase.FINISHING, dragX = 0f, dragY = 0f, paused = false) }
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
            state.phase == Phase.REVIEWING -> {
                state.review?.let { review -> enqueue { recorder.discard(review.recording) } }
                state.voiceReview?.let { review -> enqueue { recorder.discardVoice(review.recording) } }
            }
        }
        if (state.phase != Phase.FINISHING) _state.update { it.copy(phase = Phase.IDLE, review = null, voiceReview = null, paused = false) }
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
        show(recorder.startFailure(mode) ?: if (mode == RecordingMode.VOICE) "Не удалось включить микрофон" else "Не удалось включить камеру")
    }

    private fun discard(mode: RecordingMode) = enqueue { recorder.cancel(mode) }

    /** Включение, остановка и выброс идут по очереди: следующее нажатие ждёт выключения. */
    private fun enqueue(operation: suspend () -> Unit) {
        scope.launch { queue.withLock { operation() } }
    }

    /** Короткое касание: у микрофона — подсказка, у камеры — снимок. */
    private fun tapped(mode: RecordingMode) {
        if (mode == RecordingMode.VIDEO) onCameraTap() else show(RecordingGesture.HOLD_HINT)
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
        /** Микрофон: нажатие короче — подсказка, дольше — запись. */
        const val HOLD_DELAY_MS = 150L

        /** Камера: нажатие короче — снимок, дольше — кружок. */
        const val VIDEO_HOLD_DELAY_MS = 280L

        /** Кружок — не длиннее минуты. */
        const val VIDEO_NOTE_LIMIT_MS = 60_000L

        /** Обрезанный кружок — не короче секунды. */
        const val NOTE_MINIMUM_MS = 1_000L
    }
}
