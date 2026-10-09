package app.maxly.presentation.chat

import app.maxly.SharedFixtures
import app.maxly.SharedFixtures.Companion.array
import app.maxly.SharedFixtures.Companion.long
import app.maxly.SharedFixtures.Companion.obj
import app.maxly.SharedFixtures.Companion.raw
import app.maxly.SharedFixtures.Companion.str
import app.maxly.data.CoreDraftRepository
import app.maxly.data.DraftCodec
import app.maxly.data.DraftRepository
import app.maxly.data.TextMarks
import app.maxly.domain.ChatDraft
import app.maxly.domain.TextSpan
import com.max.core.api.Chat
import com.max.core.api.Drafts
import com.max.core.state.MaxState
import com.max.core.state.StateReducer
import com.max.core.auth.RequestSink
import com.max.core.protocol.CmdType
import com.max.core.protocol.Opcode
import com.max.core.protocol.PROTOCOL_VERSION
import com.max.core.protocol.PacketHeader
import com.max.core.transport.TransportPacket
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Общие с iOS сценарии черновиков из `test-fixtures/drafts` (правила — в README каталога).
 *
 * `merge`: черновик сервера и отметка стирания — `LOGIN` через ядро ([Drafts.fromLogin],
 * [StateReducer.putDrafts]); черновик устройства — через [DraftCodec] (так он лежит в настройках);
 * выбор — [CoreDraftRepository.reconcile] с правилом ядра над этим стором, ровно как
 * `MaxClient.reconcileDraft` при открытии чата.
 *
 * `outgoing`: [DraftSync] над сервером, который делает то же, что [CoreDraftRepository] и
 * `MaxClient`: сохранение — [CoreDraftRepository.request] и `DRAFT_SAVE` ядра по адресу
 * [Drafts.address], стирание — `DRAFT_DISCARD` со временем черновика сервера.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DraftsFixtureTest {
    private val fixtures = SharedFixtures("drafts")

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures.files()
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        assertTrue("сыграно ${fixtures.played} случаев", fixtures.played >= files.size)
        fixtures.finish("DraftsFixtureTest", files.size)
    }

    private fun play(file: String, fixture: JsonObject) {
        val kind = fixture["kind"].str
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["name"].str}") {
                when (kind) {
                    "merge" -> merge(case)
                    "outgoing" -> outgoing(case)
                    else -> error("$file: незнакомый kind $kind")
                }
            }
        }
    }

    // ---- kind: merge -----------------------------------------------------------------------------

    private fun SharedFixtures.Case.merge(case: JsonObject) {
        val me = 100L
        val chatId = -7000L
        val chats = linkedMapOf<String, Any?>()
        case["server"].obj?.let { chats["saved"] = mapOf(chatId.toString() to serverRaw(it)) }
        case["discardedAt"].long?.let { chats["discarded"] = mapOf(chatId.toString() to it) }
        val snapshot = Drafts.fromLogin(mapOf("drafts" to mapOf("chats" to chats)), me)
        val state = StateReducer.putDrafts(MaxState(me = me), snapshot)
        val local = case["local"].obj?.let { DraftCodec.decode(DraftCodec.encode(draft(it))) }
        val shown = CoreDraftRepository.reconcile(chatId, local) { Drafts.reconcile(it, state.draftOf(chatId), state.draftDiscardedAt(chatId)) }
        check("draft", case["expect"].obj?.let(::key), shown?.let(::key))
    }

    /** Черновик сервера в `LOGIN`: `{saveTime, text, elements, replyTo?}`. */
    private fun serverRaw(value: JsonObject): Map<String, Any?> {
        val draft = draft(value)
        return buildMap {
            put("saveTime", draft.updatedAtMs)
            put("text", draft.text)
            put("elements", TextMarks.toElements(draft.text, draft.formatting).map { it.toPayload() })
            draft.replyTo?.let { put("replyTo", it.toLong()) }
        }
    }

    // ---- kind: outgoing --------------------------------------------------------------------------

    private fun SharedFixtures.Case.outgoing(case: JsonObject) {
        val me = case["me"].long!!
        val chat = case["chat"].obj!!
        val chatId = chat["id"].long!!
        val type = when (val t = chat["type"].str) {
            "DIALOG", "CHAT", "CHANNEL" -> t
            else -> error("незнакомый type $t")
        }
        val participants = listOfNotNull(me, chat["peerId"].long).associate { it.toString() to 0L }
        val coreChat = Chat.from(mapOf("id" to chatId, "type" to type, "participants" to participants))!!
        val sink = RecordingSink()
        val remote = CoreLikeDrafts(sink, Drafts.address(chatId, coreChat, me), case["server"].obj?.let(::draft))
        val scope = TestScope(StandardTestDispatcher())
        val sync = DraftSync(scope, remote, delayMs = 1_000)
        val local = case["local"].obj?.let(::draft)
        sync.changed(chatId.toString(), local)
        sync.flush(chatId.toString())
        scope.runCurrent()

        val expect = case["expect"].obj!!
        check("запросов", if (expect["request"].str == null) 0 else 1, sink.sent.size)
        val (opcode, payload) = sink.sent.firstOrNull() ?: return
        check("request", expect["request"].str, opcode.name)
        check("payload", canon(expect["payload"]?.raw(), ids = false), canon(payload, ids = true))
    }

    /** Сервер черновиков одного чата, как его видит [DraftSync] через [CoreDraftRepository] и `MaxClient`. */
    private class CoreLikeDrafts(sink: RequestSink, private val address: com.max.core.api.DraftAddress, private var stored: ChatDraft?) : DraftRepository {
        private val api = com.max.core.api.MaxApi(sink).drafts
        override val drafts: Flow<Map<String, ChatDraft>> = flowOf(emptyMap())
        override fun current(chatId: String): ChatDraft? = stored
        override fun reconcile(chatId: String, local: ChatDraft?): ChatDraft? = error("сценарий outgoing не выбирает черновик")

        override suspend fun save(chatId: String, draft: ChatDraft) {
            val request = CoreDraftRepository.request(draft)
            // MaxClient.saveDraft: элементы, что не влезают в текст, не уходят.
            val time = api.saveDraft(address, request.text, request.elements.filter { it.fits(request.text.length) }, request.replyTo)
            stored = draft.copy(updatedAtMs = time)
        }

        override suspend fun discard(chatId: String) {
            // MaxClient.discardDraft: время — updateTime черновика сервера; без него ничего не уходит.
            val at = stored?.updatedAtMs ?: return
            api.discardDraft(address, at)
            stored = null
        }
    }

    private class RecordingSink : RequestSink {
        val sent = mutableListOf<Pair<Opcode, Any?>>()
        override suspend fun request(opcode: Opcode, payload: Any?): TransportPacket {
            sent += opcode to payload
            val body: Any? = when (opcode) {
                Opcode.DRAFT_SAVE -> mapOf("time" to 9_000L)
                Opcode.DRAFT_DISCARD -> emptyMap<String, Any?>()
                else -> error("неожиданный запрос $opcode")
            }
            return TransportPacket(PacketHeader(PROTOCOL_VERSION, CmdType.OK.value, 1, opcode.value.toShort(), 0, false), body)
        }
    }

    // ---- помощники ------------------------------------------------------------------------------

    private fun draft(value: JsonObject) = ChatDraft(
        text = value["text"].str!!,
        updatedAtMs = value["updateTime"].long!!,
        formatting = spans(value["spans"]),
        replyTo = value["replyTo"].str,
    )

    private fun spans(value: JsonElement?): List<TextSpan> = value.array.map {
        it as JsonObject
        TextSpan(TextSpan.Kind.valueOf(it["type"].str!!), it["from"].long!!.toInt(), it["length"].long!!.toInt(), url = it["url"].str)
    }

    private fun key(draft: ChatDraft) = listOf(draft.text, draft.updatedAtMs, draft.replyTo, draft.formatting.map { "${it.kind} ${it.from}+${it.length}" }.sorted())

    private fun key(value: JsonObject) = key(draft(value))

    /** Тело запроса для сравнения: ключи по алфавиту, числа — `Long`; [ids] — id (`chatId`, `userId`, `replyTo`) строками, как в сценарии. */
    private fun canon(value: Any?, ids: Boolean, field: String? = null): Any? = when (value) {
        is Number -> if (ids && field in ID_FIELDS) value.toLong().toString() else value.toLong()
        is Map<*, *> -> value.entries.associate { (k, v) -> k.toString() to canon(v, ids, k.toString()) }.toSortedMap()
        is List<*> -> value.map { canon(it, ids) }
        else -> value
    }

    private companion object {
        val ID_FIELDS = setOf("chatId", "userId", "replyTo")
    }
}
