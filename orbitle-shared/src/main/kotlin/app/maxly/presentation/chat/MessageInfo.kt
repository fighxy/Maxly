package app.maxly.presentation.chat

import app.maxly.data.MessageRepository
import app.maxly.domain.Chat
import app.maxly.domain.ChatType
import app.maxly.domain.Message
import app.maxly.domain.MessageReader
import app.maxly.domain.MessageStatus
import app.maxly.presentation.common.PresenceText
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
 *
 * Ядро не знает двух правил общих сценариев `test-fixtures/readers`, их проверяет клиент:
 * «Избранное» ([Chat.SAVED_MESSAGES_ID]) и состояние сообщения (только отправленное на сервер).
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

    /** Строка прочтения своего сообщения в личном чате. */
    enum class Delivery(val text: String) { READ("Прочитано"), DELIVERED("Доставлено") }

    private val _state = MutableStateFlow(MessageInfoState(phase = if (showsReaders) MessageInfoState.Phase.Loading else MessageInfoState.Phase.Unavailable))
    val state: StateFlow<MessageInfoState> = _state.asStateFlow()

    val title: String get() = "Сведения"

    /**
     * Блок «Кем прочитано» есть только в группах и только у сообщения на сервере; окончательно
     * решает ядро (размер группы, звонок).
     */
    val showsReaders: Boolean
        get() = chatType == ChatType.GROUP && chatId != Chat.SAVED_MESSAGES_ID && isOnServer(message)

    /**
     * «Прочитано» / «Доставлено»: только своё отправленное сообщение в личном чате, кроме
     * «Избранного». Прочитано — отметка собеседника не раньше сообщения ([Message.isRead]).
     */
    val delivery: Delivery?
        get() {
            if (!mine || chatType != ChatType.PRIVATE || chatId == Chat.SAVED_MESSAGES_ID || !isOnServer(message)) return null
            return if (message.isRead) Delivery.READ else Delivery.DELIVERED
        }

    val rows: List<Row>
        get() = buildList {
            add(Row("Отправлено", dateTime(message.timeMs, zone)))
            val editedAt = message.content.editedAtMs
            if (message.content.edited || editedAt != null) add(Row("Изменено", editedAt?.let { dateTime(it, zone) }.orEmpty()))
            message.content.forward?.let { add(Row("Переслано из", it.authorName)) }
            delivery?.let { add(Row("Статус", it.text)) }
        }

    /** Подпись под прочитавшим: «Прочитано · время» по его отметке; без отметки (только реакция) — нет. */
    fun readText(reader: MessageReader): String? =
        reader.readMarkMs?.takeIf { it > 0 }?.let { "Прочитано · ${dateTime(it, zone)}" }

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
        /**
         * Пункт «Сведения» в меню: у любого сообщения на сервере, кроме служебных. У того, что ещё
         * отправляется или не ушло, его нет; запланированные живут отдельным списком и сюда не попадают.
         */
        fun isOffered(message: Message): Boolean = isOnServer(message) && !message.isService

        private fun isOnServer(message: Message): Boolean =
            message.status == MessageStatus.SENT && message.id.toLongOrNull() != null

        /** «8 октября 2026, 16:44». */
        fun dateTime(ms: Long, zone: ZoneId): String {
            val d = Instant.ofEpochMilli(ms).atZone(zone)
            val month = PresenceText.MONTHS_GENITIVE[d.monthValue - 1]
            return "${d.dayOfMonth} $month ${d.year}, %02d:%02d".format(d.hour, d.minute)
        }

        fun name(reader: MessageReader): String = reader.name.ifBlank { "Пользователь" }
    }
}
