package app.orbitle.presentation.chat

import app.orbitle.data.MessageMapping
import app.orbitle.data.MessageRepository
import app.orbitle.domain.ChatType
import app.orbitle.domain.Message
import app.orbitle.domain.MessageReader
import app.orbitle.domain.MessageStatus
import com.max.core.api.AccountConfig
import com.max.core.api.Chat
import com.max.core.api.MaxApi
import com.max.core.api.MaxMessage
import com.max.core.api.MessageReaders
import com.max.core.auth.RequestSink
import com.max.core.protocol.CmdType
import com.max.core.protocol.Opcode
import com.max.core.protocol.PROTOCOL_VERSION
import com.max.core.protocol.PacketHeader
import com.max.core.state.MaxState
import com.max.core.transport.TransportPacket
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.lang.reflect.Proxy
import java.time.ZoneOffset

/**
 * Общие с iOS сценарии «Кем прочитано» и строки прочтения из `test-fixtures/readers` (формат и
 * правила — в README каталога). Играются все файлы каталога; незнакомый `kind` — ошибка.
 *
 * Путь тот же, что у клиентов: пункт меню — [MessageInfoModel.isOffered]; блок и статус —
 * [MessageInfoModel] (клиентские правила: «Избранное», состояние сообщения); список — ядро:
 * `MaxClient.isMessageReadersAvailable` ([MessageReaders.isAvailable] с `max-readmarks` из
 * [AccountConfig]) и `MaxClient.loadMessageReaders` ([com.max.core.api.ReadersApi] над поддельным
 * сокетом: `CHAT_INFO`, `CHAT_MEMBERS`, `MSG_GET_DETAILED_REACTIONS` отвечают данными сценария),
 * затем [MessageMapping.reader], как в `CoreMessageRepository.messageReaders`. Пуши 130 при открытом
 * списке сливаются [MessageReaders.mergeMarks].
 */
class ReadersFixtureTest {
    private val zone = ZoneOffset.UTC

    /**
     * Сценарии, которые пока расходятся с ядром из-за известной недоработки ядра (повтор ключа в
     * `participants` — ядро берёт последнее значение, правка в max-kmp-core feat/evening).
     * Ключ — `файл` или `файл / случай`, значение — почему. Сейчас пусто.
     */
    private val pendingInCore: Map<String, String> = emptyMap()

    private var played = 0

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures().listFiles { file -> file.extension == "json" }.orEmpty().sortedBy { it.name }
        assertTrue("нет сценариев в ${fixtures()}", files.isNotEmpty())
        for (file in files) {
            val fixture = parse(file.readText())
            assertEquals("${file.name}: name", file.nameWithoutExtension, fixture["name"].str)
            when (val kind = fixture["kind"].str) {
                "readers" -> readers(file.nameWithoutExtension, fixture)
                "info" -> info(file.nameWithoutExtension, fixture)
                "edited" -> edited(file.nameWithoutExtension, fixture)
                else -> error("${file.name}: незнакомый kind $kind")
            }
        }
        assertTrue("сыграно $played случаев", played >= files.size)
        println("ReadersFixtureTest: ${files.size} файлов, $played случаев")
    }

    /** Поломанный ожидаемый список ловится: проигрыватель не проходит молча. */
    @Test
    fun brokenExpectationFails() {
        val file = File(fixtures(), "reactors-first.json")
        val broken = file.readText().replaceFirst("\"readMark\": 6000", "\"readMark\": 6001")
        check(broken != file.readText()) { "в reactors-first нет readMark 6000" }
        val failure = runCatching { readers("reactors-first", parse(broken)) }.exceptionOrNull()
        assertTrue("сломанный сценарий прошёл", failure is AssertionError)
    }

    // ---- kind: readers -----------------------------------------------------------------------

    private fun readers(file: String, fixture: JsonObject) {
        pendingInCore[file]?.let { println("ПРОПУСК $file: $it"); return }
        val chat = fixture["chat"] as JsonObject
        val message = fixture["message"] as JsonObject
        val me = fixture["me"].id!!
        val author = message["author"].id
        val time = message["time"].long!!
        val chatId = chat["id"].str!!
        val coreChatId = coreChatId(chatId)
        val maxReadmarks = config(fixture["serverMaxReadmarks"]).maxReadmarks
        val rawChat = LinkedHashMap<String, Any?>((chat.raw() as Map<*, *>).mapKeys { it.key as String }).apply { put("id", coreChatId) }
        val rawMessage = mapOf("id" to MESSAGE_ID, "chatId" to coreChatId, "time" to time, "type" to "USER", "sender" to message["author"]?.raw(), "text" to "привет")
        val sink = FixtureSink(rawChat, rawMessage, fixture["reactions"]?.raw(), fixture["reactionsError"].bool == true)
        val pushed = Chat.readMarks(fixture["pushedMarks"]?.raw())

        // Сообщение, каким его видит экран: отправленное — из ядра через MessageMapping, остальное — локальное.
        val clientMessage = clientMessage(message["state"].str!!, MaxMessage.from(rawMessage, coreChatId)!!, coreChatId, me, peerRead = 0)
        val repository = FixtureRepository(sink, coreChatId, me, maxReadmarks, rawMessage)
        var live = pushed

        fun check(expect: JsonObject, where: String) {
            played++
            val wantAvailable = expect["available"].bool!!
            val want = (expect["readers"] as JsonArray).map {
                it as JsonObject
                Triple(it["userId"].str!!, it["reaction"].str, it["readMark"].long)
            }
            if (clientMessage == null || !MessageInfoModel.isOffered(clientMessage)) {
                // «Сведения» в меню нет — нет и списка.
                assertEquals("$where: available (пункта меню нет)", wantAvailable, false)
                assertEquals("$where: readers", want, emptyList<Triple<String, String?, Long?>>())
                return
            }
            repository.live = live
            val asked = repository.asked
            val model = MessageInfoModel(chatId, clientMessage, ChatType.fromCore(chat["type"].str!!), author == me, repository, TestScope(UnconfinedTestDispatcher()), zone)
            model.load()
            val state = model.state.value
            val available = model.showsReaders && state.phase != MessageInfoState.Phase.Unavailable
            assertEquals("$where: available (phase ${state.phase})", wantAvailable, available)
            if (!model.showsReaders) assertEquals("$where: ядро не спрашивали", asked, repository.asked)
            if (available) assertEquals("$where: phase", MessageInfoState.Phase.Loaded, state.phase)
            val actual = state.readers.map { Triple(it.userId, it.emoji, it.readMarkMs) }
            assertEquals("$where: readers", want, actual)
            assertEquals("$where: emptyText", if (available && want.isEmpty()) "Пока никто не прочитал" else null, state.emptyText)
            // Строка «Прочитано · время» — по отметке, у отреагировавшего без отметки её нет.
            state.readers.forEach { r -> assertEquals("$where: readText ${r.userId}", r.readMarkMs != null, model.readText(r) != null) }
        }

        check(fixture["expect"] as JsonObject, file)
        (fixture["steps"] as? JsonArray).orEmpty().forEachIndexed { index, step ->
            step as JsonObject
            val push = step["push"] as JsonObject
            live = MessageReaders.mergeMarks(live, mapOf(push["userId"].id!! to push["mark"].long!!))
            check(step["expect"] as JsonObject, "$file / шаг ${index + 1}")
        }
    }

    // ---- kind: info --------------------------------------------------------------------------

    private fun info(file: String, fixture: JsonObject) {
        val cases = fixture["cases"] as JsonArray
        assertTrue("$file: нет случаев", cases.isNotEmpty())
        val me = 1L
        val peer = 2L
        for (case in cases) {
            case as JsonObject
            val where = "$file / ${case["name"].str}"
            val pending = pendingInCore[where]
            if (pending != null) {
                println("ПРОПУСК $where: $pending")
                continue
            }
            played++
            val chat = case["chat"] as JsonObject
            val chatId = chat["id"].str!!
            val coreChatId = coreChatId(chatId)
            val own = case["own"].bool!!
            val raw = mapOf("id" to MESSAGE_ID, "chatId" to coreChatId, "time" to case["messageTime"].long!!, "type" to "USER", "sender" to if (own) me else peer, "text" to "привет")
            val message = clientMessage(case["state"].str!!, MaxMessage.from(raw, coreChatId)!!, coreChatId, me, peerRead = case["peerMark"].long!!)
            val expect = case["expect"] as JsonObject
            val model = message?.let { MessageInfoModel(chatId, it, ChatType.fromCore(chat["type"].str!!), own, unusedRepository(), TestScope(UnconfinedTestDispatcher()), zone) }
            val delivery = model?.delivery
            assertEquals("$where: status", expect["status"].str, delivery?.name?.lowercase())
            assertEquals("$where: text", expect["text"].str, delivery?.text)
            assertEquals("$where: строка «Статус»", expect["text"].str, model?.rows?.firstOrNull { it.label == "Статус" }?.value)
        }
    }

    // ---- kind: edited ------------------------------------------------------------------------

    private fun edited(file: String, fixture: JsonObject) {
        val cases = fixture["cases"] as JsonArray
        assertTrue("$file: нет случаев", cases.isNotEmpty())
        for (case in cases) {
            case as JsonObject
            val where = "$file / ${case["name"].str}"
            played++
            val raw = linkedMapOf<String, Any?>("id" to MESSAGE_ID, "chatId" to 100L, "time" to 5_000L, "type" to "USER", "sender" to 2L, "text" to "привет")
            if (case.containsKey("updateTime")) raw["updateTime"] = case["updateTime"]!!.raw()
            val message = MessageMapping.message(MaxMessage.from(raw, 100L)!!, 100L, MaxState(me = 1L))
            val expect = case["expect"] as JsonObject
            val model = MessageInfoModel("100", message, ChatType.GROUP, false, unusedRepository(), TestScope(UnconfinedTestDispatcher()), zone)
            val row = model.rows.firstOrNull { it.label == "Изменено" }
            assertEquals("$where: edited", expect["edited"].bool!!, row != null)
            assertEquals("$where: time", expect["time"].long, message.content.editedAtMs)
            val time = expect["time"].long
            assertEquals("$where: строка", time?.let { MessageInfoModel.dateTime(it, zone) }, row?.value?.takeIf { it.isNotEmpty() })
        }
    }

    // ---- клиент и ядро -----------------------------------------------------------------------

    /**
     * Сообщение экрана: `sent` — серверное через [MessageMapping.message] (признак прочтения — по
     * отметке собеседника [peerRead]); `sending` / `failed` — локальное без серверного id, как его
     * держит чат до ответа сервера; `scheduled` — `null`: запланированные клиент показывает
     * отдельным списком без «Сведений», в ленте их нет.
     */
    private fun clientMessage(state: String, message: MaxMessage, chatId: Long, me: Long, peerRead: Long): Message? {
        val sent = MessageMapping.message(message, chatId, MaxState(me = me), peerRead)
        return when (state) {
            "sent" -> sent
            "sending" -> sent.copy(id = "local-1", status = MessageStatus.SENDING, isRead = false)
            "failed" -> sent.copy(id = "local-1", status = MessageStatus.FAILED, isRead = false)
            "scheduled" -> null
            else -> error("незнакомое state $state")
        }
    }

    /**
     * `CoreMessageRepository.messageReaders` без `MaxClient`: те же шаги ядра (`isMessageReadersAvailable`,
     * `loadMessageReaders` с отметками пушей) и тот же [MessageMapping.reader].
     */
    private class FixtureRepository(
        private val sink: FixtureSink,
        private val chatId: Long,
        private val me: Long,
        private val maxReadmarks: Int,
        private val message: Map<String, Any?>,
    ) : MessageRepository by unusedRepository() {
        var live: Map<Long, Long> = emptyMap()
        var asked = 0

        override suspend fun messageReaders(chatId: String, messageId: String): List<MessageReader>? {
            asked++
            val stored = Chat.from(sink.chat)!!
            if (!MessageReaders.isAvailable(stored, maxReadmarks)) return null
            val result = MaxApi(sink).readers.loadMessageReaders(
                this.chatId,
                messageId.toLong(),
                me = me,
                maxReadmarks = maxReadmarks,
                liveMarks = live,
                message = MaxMessage.from(message, this.chatId),
            )
            if (result.readers.isEmpty() && !MessageReaders.isAvailable(result.chat, maxReadmarks)) return null
            return result.readers.map { MessageMapping.reader(it, null) }
        }
    }

    /** Ответы сервера из сценария; ошибка 181 — исключение, как у сокета. */
    private class FixtureSink(val chat: Map<String, Any?>, val message: Map<String, Any?>, val reactions: Any?, val reactionsError: Boolean) : RequestSink {
        override suspend fun request(opcode: Opcode, payload: Any?): TransportPacket {
            val body: Any? = when (opcode) {
                Opcode.CHAT_INFO -> mapOf("chats" to listOf(chat))
                Opcode.MSG_GET -> mapOf("messages" to listOf(message))
                Opcode.CHAT_MEMBERS -> mapOf("members" to emptyList<Any>(), "marker" to 0L)
                Opcode.MSG_GET_DETAILED_REACTIONS ->
                    if (reactionsError) throw IllegalStateException("181 не удался") else mapOf("reactions" to (reactions ?: emptyList<Any>()))
                else -> error("неожиданный запрос $opcode")
            }
            return TransportPacket(PacketHeader(PROTOCOL_VERSION, CmdType.OK.value, 1, opcode.value.toShort(), 0, false), body)
        }
    }

    private fun config(serverMaxReadmarks: JsonElement?): AccountConfig =
        serverMaxReadmarks?.raw()?.let { AccountConfig(server = mapOf("max-readmarks" to it)) } ?: AccountConfig()

    /** id чата сценария для ядра: «Избранное» — `0`, остальные (`c1`) — числом. */
    private fun coreChatId(id: String): Long = id.toLongOrNull() ?: (1_000L + id.hashCode().toLong().and(0xffff))

    private fun parse(text: String): JsonObject = Json.parseToJsonElement(text) as JsonObject

    private fun JsonElement.raw(): Any? = when (this) {
        is JsonNull -> null
        is JsonPrimitive -> if (isString) content else longOrNull ?: booleanOrNull ?: doubleOrNull
        is JsonObject -> LinkedHashMap<String, Any?>().also { out -> forEach { (k, v) -> out[k] = v.raw() } }
        is JsonArray -> map { it.raw() }
    }

    private val JsonElement?.str: String? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
    private val JsonElement?.long: Long? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.let { it.longOrNull ?: it.contentOrNull?.toLongOrNull() }
    private val JsonElement?.bool: Boolean? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.booleanOrNull
    private val JsonElement?.id: Long? get() = long

    private fun fixtures(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "test-fixtures/readers")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        error("нет каталога test-fixtures/readers выше ${File("").absolutePath}")
    }

    private companion object {
        const val MESSAGE_ID = 42L

        fun unusedRepository(): MessageRepository = Proxy.newProxyInstance(
            MessageRepository::class.java.classLoader,
            arrayOf(MessageRepository::class.java),
        ) { _, method, _ -> error("не нужен: ${method.name}") } as MessageRepository
    }
}
