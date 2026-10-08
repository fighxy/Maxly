package app.orbitle.data.calls

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.concurrent.TimeUnit

/** Сокет сигнального сервера звонков (ws2): текстовые кадры в обе стороны. */
interface Ws2Socket {
    suspend fun send(text: String)

    /** Следующий текстовый кадр. Исключение — сокет закрыт. */
    suspend fun receive(): String

    fun close()
}

/** Открывает сокет ws2 по полному адресу. */
typealias Ws2Connector = suspend (url: String) -> Ws2Socket

sealed class Ws2Exception(message: String) : Exception(message) {
    /** Сокет закрыт: ответа уже не будет. */
    class Closed : Ws2Exception("ws2 closed")

    /** Сервер не ответил на команду за отведённое время. */
    class Timeout(val command: String) : Ws2Exception("ws2 timeout: $command")

    /** Сервер ответил на команду ошибкой, например `conversation-ended`. */
    class Command(val command: String, val error: String) : Ws2Exception("ws2 $command: $error")
}

/**
 * Сигнальный канал звонка поверх ws2.
 *
 * Конверт сообщений (схема Komet `ws2_signaling.dart`, kolibri-net `calls/signaling.rs`):
 * - команда: `{"command": …, …, "sequence": N}`, номера с 1;
 * - ответ: `{"sequence": N, "response": "<команда>", "type": "response"}`;
 * - ошибка: `{"sequence": N, "type": "error", "error": …}` — она же уходит в уведомления;
 * - уведомление: `{"notification": "<имя>", "type": "notification", …}`;
 * - текстовый кадр `ping` — ответ `pong`.
 *
 * Кадры уходят строго по порядку: SDP раньше кандидатов, которые после него.
 */
class Ws2Signaling(
    private val socket: Ws2Socket,
    private val scope: CoroutineScope,
    private val timeoutMs: Long = 15_000,
) {
    private val notify = Channel<JsonObject>(Channel.UNLIMITED)
    private val outbox = Channel<String>(Channel.UNLIMITED)
    private val pending = HashMap<Long, Pair<String, CompletableDeferred<JsonObject>>>()
    private var sequence = 0L
    private var reader: Job? = null
    private var writer: Job? = null

    @Volatile
    var isClosed = false
        private set

    /** Уведомления сервера и ошибки команд по порядку прихода. Канал закрывается вместе с сокетом. */
    val notifications: ReceiveChannel<JsonObject> get() = notify

    /** Запускает чтение и запись. Повторный вызов ничего не делает. */
    fun run() {
        synchronized(this) {
            if (reader != null || isClosed) return
            writer = scope.launch {
                try {
                    for (text in outbox) socket.send(text)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    finish()
                }
            }
            reader = scope.launch {
                try {
                    while (true) route(socket.receive())
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    finish()
                }
            }
        }
    }

    /** Отправляет команду и ждёт ответ. Ответ-ошибка бросает [Ws2Exception.Command]. */
    suspend fun send(command: String, extra: Map<String, JsonElement> = emptyMap()): JsonObject {
        val reply = CompletableDeferred<JsonObject>()
        val number: Long
        synchronized(this) {
            if (isClosed) throw Ws2Exception.Closed()
            number = ++sequence
            pending[number] = command to reply
            val body = LinkedHashMap(extra)
            body["command"] = JsonPrimitive(command)
            body["sequence"] = JsonPrimitive(number)
            outbox.trySend(JsonObject(body).toString())
        }
        val response = withTimeoutOrNull(timeoutMs) { reply.await() }
        if (response == null) {
            synchronized(this) { pending.remove(number) }
            throw Ws2Exception.Timeout(command)
        }
        val error = response["error"]
        if (response["type"].str == "error" || !error.isNull) throw Ws2Exception.Command(command, describe(error))
        return response
    }

    /** Закрывает сокет. Ждущие ответа команды получают [Ws2Exception.Closed]. */
    fun close() {
        if (isClosed) return
        socket.close()
        reader?.cancel()
        finish()
    }

    internal fun route(text: String) {
        if (text == "ping") {
            outbox.trySend("pong")
            return
        }
        val message = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: return
        val type = message["type"].str
        if (type == "response" || type == "error") {
            val number = message["sequence"].long
            val waiter = synchronized(this) { number?.let { pending.remove(it) } }
            waiter?.second?.complete(message)
            if (type == "error") notify.trySend(message)
            return
        }
        if (type == "notification" || message["notification"] != null) notify.trySend(message)
    }

    private fun finish() {
        val waiting: Collection<Pair<String, CompletableDeferred<JsonObject>>>
        synchronized(this) {
            val wasClosed = isClosed
            isClosed = true
            waiting = pending.values.toList()
            pending.clear()
            if (wasClosed) {
                waiting.forEach { it.second.completeExceptionally(Ws2Exception.Closed()) }
                return
            }
        }
        waiting.forEach { it.second.completeExceptionally(Ws2Exception.Closed()) }
        notify.close()
        outbox.close()
        writer?.cancel()
    }

    private fun describe(error: JsonElement?): String = when {
        error == null || error is JsonNull -> "error"
        error.str != null -> error.str!!
        else -> error.toString()
    }

    companion object {
        /** Открывает сокет и начинает читать его. */
        suspend fun connect(url: String, connector: Ws2Connector, scope: CoroutineScope, timeoutMs: Long = 15_000): Ws2Signaling {
            val signaling = Ws2Signaling(connector(url), scope, timeoutMs)
            signaling.run()
            return signaling
        }
    }
}

/** Сокет ws2 на OkHttp: им же ходит SDK звонков, сервер видит привычный `okhttp/4.12.0`. */
class OkHttpWs2Socket private constructor() : Ws2Socket {
    private val incoming = Channel<String>(Channel.UNLIMITED)
    private val opened = CompletableDeferred<Unit>()
    private var socket: WebSocket? = null

    override suspend fun send(text: String) {
        val socket = socket ?: throw Ws2Exception.Closed()
        if (!socket.send(text)) throw Ws2Exception.Closed()
    }

    override suspend fun receive(): String = try {
        incoming.receive()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        throw Ws2Exception.Closed()
    }

    override fun close() {
        socket?.close(1000, null)
        incoming.close()
        opened.completeExceptionally(Ws2Exception.Closed())
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            opened.complete(Unit)
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            incoming.trySend(text)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            incoming.trySend(bytes.utf8())
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(1000, null)
            incoming.close()
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            incoming.close()
            opened.completeExceptionally(Ws2Exception.Closed())
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            incoming.close()
            opened.completeExceptionally(t)
        }
    }

    companion object {
        private val client by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .pingInterval(0, TimeUnit.SECONDS)
                .build()
        }

        /** Открывает сокет и ждёт рукопожатия (не дольше 15 с). */
        suspend fun connect(url: String): Ws2Socket {
            val socket = OkHttpWs2Socket()
            val request = Request.Builder().url(url).header("User-Agent", "okhttp/4.12.0").build()
            socket.socket = client.newWebSocket(request, socket.listener)
            val ok = withTimeoutOrNull(15_000) { socket.opened.await() }
            if (ok == null) {
                socket.close()
                throw Ws2Exception.Timeout("connect")
            }
            return socket
        }
    }
}

/** Кому слать SDP и кандидатов: номер участника, тип и номер устройства. */
data class CallPeerAddress(val id: Long, val type: String = "USER", val deviceIdx: Long = 0)

/** Тела команд ws2 (схема Komet `ws2_signaling.dart`). */
object Ws2Command {
    /** `hexCapability` SDK звонков: его же сервер видит в `internalParams`. */
    const val CAPABILITIES = "3c02f"

    /** Что сейчас отправляется: звук, камера, экран. */
    fun mediaSettings(audio: Boolean, video: Boolean, screen: Boolean): JsonObject = json(
        "isVideoEnabled" to video,
        "isAudioEnabled" to audio,
        "isScreenSharingEnabled" to screen,
        "isAnimojiEnabled" to false,
    )

    fun transmit(sdp: SessionDescription, to: CallPeerAddress): Map<String, JsonElement> = json(
        "participantId" to to.id,
        "participantType" to to.type,
        "deviceIdx" to to.deviceIdx,
        "data" to mapOf("sdp" to mapOf("type" to sdp.type.raw, "sdp" to sdp.sdp)),
        "capabilities" to CAPABILITIES,
    )

    fun transmit(candidate: IceCandidate, to: CallPeerAddress): Map<String, JsonElement> = json(
        "participantId" to to.id,
        "participantType" to to.type,
        "deviceIdx" to to.deviceIdx,
        "data" to mapOf(
            "candidate" to mapOf(
                "candidate" to candidate.sdp,
                "sdpMid" to (candidate.sdpMid ?: "0"),
                "sdpMLineIndex" to candidate.sdpMLineIndex,
            ),
        ),
    )

    /** `allocate-consumer`: что клиент умеет принимать от SFU. */
    val allocateConsumer: Map<String, JsonElement> = json(
        "capabilities" to mapOf(
            "maxH264Decoders" to 10,
            "producerNotificationDataChannelVersion" to 7,
            "producerCommandDataChannelVersion" to 2,
            "audioMix" to true,
            "consumerUpdate" to true,
            "onDemandTracks" to true,
            "singleSession" to true,
            "unifiedPlan" to true,
            "fastScreenShare" to true,
            "consumerFastScreenShareQualityOnDemand" to true,
            "red" to true,
            "videoTracksCount" to 10,
            "csrcAccessible" to true,
        ),
    )

    /** `record-start` с теми же полями, что шлёт Komet: всё, кроме `streamMovie`, пустое. */
    val recordStart: Map<String, JsonElement> = json(
        "movieId" to null,
        "name" to null,
        "description" to null,
        "privacy" to null,
        "groupId" to null,
        "albumId" to null,
        "streamMovie" to false,
    )
}
