package app.orbitle.presentation.chat

import app.orbitle.data.MessageRepository
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageReader
import app.orbitle.domain.MessageStatus
import app.orbitle.presentation.common.PresenceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

data class MessageInfoState(
    val readers: List<MessageReader> = emptyList(),
    val phase: Phase = Phase.Loading,
) {
    /** [Unavailable] — сервер список не даёт: блок «Кем прочитано» не показывается. */
    enum class Phase { Loading, Loaded, Unavailable, Failed }

    val emptyText: String? get() = if (phase == Phase.Loaded && readers.isEmpty()) "Пока никто не прочитал" else null
}

/**
 * «Сведения» о сообщении: время отправки, правка, пересылка; в группе — «Кем прочитано»
 * (сначала поставившие реакцию, порядок — от ядра), в личном чате у своего — «Прочитано» или «Доставлено».
 */
class MessageInfoModel(
    private val chatId: String,
    val message: Message,
    private val chatType: ChatType?,
    private val mine: Boolean,
    private val repository: MessageRepository,
    private val scope: CoroutineScope,
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    data class Row(val label: String, val value: String)

    private val _state = MutableStateFlow(MessageInfoState(phase = if (showsReaders) MessageInfoState.Phase.Loading else MessageInfoState.Phase.Unavailable))
    val state: StateFlow<MessageInfoState> = _state.asStateFlow()

    val title: String get() = "Сведения"

    /** Блок «Кем прочитано» есть только в группах; окончательно решает ядро (размер группы, звонок). */
    val showsReaders: Boolean get() = chatType == ChatType.GROUP

    val rows: List<Row>
        get() = buildList {
            add(Row("Отправлено", dateTime(message.timeMs, zone)))
            if (message.content.edited) add(Row("Изменено", ""))
            message.content.forward?.let { add(Row("Переслано из", it.authorName)) }
            delivery()?.let { add(Row("Статус", it)) }
        }

    private fun delivery(): String? {
        if (!mine || chatType != ChatType.PRIVATE) return null
        return when (message.status) {
            MessageStatus.SENDING -> "Отправляется"
            MessageStatus.FAILED -> "Не отправлено"
            MessageStatus.SENT -> if (message.isRead) "Прочитано" else "Доставлено"
        }
    }

    fun load() {
        if (!showsReaders) return
        _state.update { it.copy(phase = MessageInfoState.Phase.Loading) }
        scope.launch {
            try {
                val readers = repository.messageReaders(chatId, message.id)
                _state.update {
                    if (readers == null) it.copy(readers = emptyList(), phase = MessageInfoState.Phase.Unavailable)
                    else it.copy(readers = readers, phase = MessageInfoState.Phase.Loaded)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _state.update { it.copy(phase = MessageInfoState.Phase.Failed) }
            }
        }
    }

    companion object {
        /** «8 октября 2026, 16:44». */
        fun dateTime(ms: Long, zone: ZoneId): String {
            val d = Instant.ofEpochMilli(ms).atZone(zone)
            val month = PresenceText.MONTHS_GENITIVE[d.monthValue - 1]
            return "${d.dayOfMonth} $month ${d.year}, %02d:%02d".format(d.hour, d.minute)
        }

        fun name(reader: MessageReader): String = reader.name.ifBlank { "Пользователь" }
    }
}
